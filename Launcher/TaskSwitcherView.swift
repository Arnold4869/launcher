import SwiftUI

// MARK: - 多任务切换器（类浏览器/安卓后台：横排实时快照卡片，可滑动）
//
// - 卡片显示页面实时缩略图（didFinish 导航后刷新）+ 标题 + 关闭钮
// - 点卡片 = 切到该页；右上角 × = 关闭
// - 卡片右上角「分屏」= 把该页设为分屏半屏，两步配对进分屏
// - 顶部「+」新开页面卡片 = 回到主页选书签

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
                    VStack(spacing: 12) {
                        Image(systemName: "square.on.square.dashed")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("没有打开的页面")
                            .font(.headline)
                        Text("回到主页点书签即可新开页面")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                newPageCard
                                ForEach(wm.pages) { page in
                                    PageCardView(page: page,
                                                 isPending: pendingTop?.id == page.bookmark.id,
                                                 onTap: { handleMainTap(page) },
                                                 onSplit: { handleSplitTap(page) },
                                                 onClose: { wm.closePage(page.id) })
                                        .id(page.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 32)
                        }
                        .onAppear {
                            if let cur = wm.pages.first(where: { $0.id == wm.fullscreenID }) {
                                proxy.scrollTo(cur.id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                wm.refreshAllSnapshots()
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

    // MARK: 交互
    private func handleMainTap(_ page: PageState) {
        if let top = pendingTop {
            guard page.bookmark.id != top.id else { pendingTop = nil; pendingTopPage = nil; return }
            wm.setPageForSplit(top, top: true, page: pendingTopPage)
            wm.setPageForSplit(page.bookmark, top: false, page: page)
            pendingTop = nil
            pendingTopPage = nil
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

    /// 先 dismiss 再改全局状态：避免 present/dismiss 竞态
    private func dismissAfter(_ apply: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: apply)
    }

    /// 从多任务切页/进分屏前，先退出当前分屏
    private func exitSplitIfNeeded() {
        wm.splitTop = nil
        wm.splitBottom = nil
        wm.splitTopPage = nil
        wm.splitBottomPage = nil
    }
}

// MARK: - 单张页面卡片（独立 View + @ObservedObject，快照/标题变化实时刷新）
private struct PageCardView: View {
    @ObservedObject var page: PageState
    let isPending: Bool
    let onTap: () -> Void
    let onSplit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
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

                VStack(spacing: 8) {
                    Button(action: onSplit) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel(isPending ? "取消" : "分屏")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(6)
            }

            Text(page.pageTitle.isEmpty ? page.bookmark.name : page.pageTitle)
                .font(.footnote)
                .lineLimit(1)
                .frame(width: 170)
        }
        .onTapGesture(perform: onTap)
    }
}
