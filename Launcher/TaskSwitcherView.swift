import SwiftUI

// MARK: - 多任务切换器（类浏览器/安卓后台：横排实时快照卡片，可滑动）
//
// - 卡片显示页面实时缩略图（didFinish 导航后刷新）+ 标题 + 关闭钮
// - 点卡片 = 切到该页；长按拖不动（保持简单）；右上角 × = 关闭
// - 卡片右上角第二按钮「分屏」= 把该页设为分屏半屏，两步配对进分屏
// - 顶部大按钮「+」回到主页选书签新开页面

struct TaskSwitcherView: View {
    @EnvironmentObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    /// 待配对的第一半（选了上半屏等待下半屏时非 nil）
    @State private var pendingTop: Bookmark?
    @State private var pendingTopPage: PageState?

    var body: some View {
        NavigationStack {
            Group {
                if wm.pages.isEmpty {
                    ContentUnavailableView("没有打开的页面",
                                           systemImage: "square.on.square.dashed",
                                           description: Text("回到主页点书签即可新开页面"))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            // 新开页面卡片（回主页选书签）
                            newPageCard
                            // 已打开页面：实时快照卡片
                            ForEach(wm.pages) { page in
                                pageCard(page)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                // 打开切换器时刷新所有页面快照（显示实时内容）
                for p in wm.pages { p.captureSnapshot() }
            }
            .navigationTitle("多任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { pendingTop = nil; pendingTopPage = nil; dismiss() }
                }
            }
        }
    }

    // MARK: 新开页面卡片
    private var newPageCard: some View {
        Button {
            pendingTop = nil; pendingTopPage = nil
            wm.goHome()
            dismissAfter { }
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 170, height: 300)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                Text("新开页面")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 页面卡片
    private func pageCard(_ page: PageState) -> some View {
        let isPending = pendingTop?.id == page.bookmark.id
        return VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // 快照
                Group {
                    if let img = page.snapshot {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(width: 170, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isPending ? Color.blue : Color.black.opacity(0.15), lineWidth: isPending ? 3 : 1)
                )
                .overlay(alignment: .topLeading) {
                    if isPending {
                        Text("分屏上半")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }

                // 右上角钮列：分屏 + 关闭
                VStack(spacing: 8) {
                    cardButton("rectangle.split.2x1", isPending ? "取消" : "分屏") {
                        handleSplitTap(page)
                    }
                    cardButton("xmark", "关闭") {
                        wm.closePage(page.id)
                    }
                }
                .padding(6)
            }

            // 标题行
            Text(page.pageTitle.isEmpty ? page.bookmark.name : page.pageTitle)
                .font(.footnote)
                .lineLimit(1)
                .frame(width: 170)
        }
        .onTapGesture { handleMainTap(page) }
    }

    private func cardButton(_ icon: String, _ accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel(accessibility)
    }

    // MARK: 交互
    private func handleMainTap(_ page: PageState) {
        if let top = pendingTop {
            // 再点等待中的那半 = 取消配对
            guard page.bookmark.id != top.id else { pendingTop = nil; pendingTopPage = nil; return }
            wm.setPageForSplit(top, top: true, page: pendingTopPage)
            wm.setPageForSplit(page.bookmark, top: false, page: page)
            pendingTop = nil
            pendingTopPage = nil
            // 回主页再进分屏：不清 fullscreenID 会残留全屏层盖住分屏
            wm.goHome()
            dismissAfter { }
        } else {
            dismissAfter {
                exitSplitIfNeeded()
                wm.fullscreenID = page.id
            }
        }
    }

    private func handleSplitTap(_ page: PageState) {
        if isPending(page) {
            // 点自己的分屏钮 = 取消配对
            pendingTop = nil; pendingTopPage = nil
            return
        }
        if let top = pendingTop {
            wm.setPageForSplit(top, top: true, page: pendingTopPage)
            wm.setPageForSplit(page.bookmark, top: false, page: page)
            pendingTop = nil
            pendingTopPage = nil
            wm.goHome()
            dismissAfter { }
        } else {
            pendingTop = page.bookmark
            pendingTopPage = page
        }
    }

    private func isPending(_ page: PageState) -> Bool {
        pendingTop?.id == page.bookmark.id
    }

    /// 先 dismiss 再改全局状态：多任务 sheet 若由全屏页呈现，先摘 sheet 再切页，避免 present/dismiss 竞态
    private func dismissAfter(_ apply: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: apply)
    }

    /// 从多任务切页/进分屏前，先退出当前分屏（否则全屏页被分屏层盖住不可见）
    private func exitSplitIfNeeded() {
        wm.splitTop = nil
        wm.splitBottom = nil
        wm.splitTopPage = nil
        wm.splitBottomPage = nil
    }
}
