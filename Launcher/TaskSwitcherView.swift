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
    /// 长按菜单入口：编辑书签 / 使用时间设置
    @State private var editingBookmark: Bookmark?
    @State private var timeLimitBookmark: Bookmark?

    var body: some View {
        NavigationStack {
            Group {
                if wm.pages.isEmpty {
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 96, height: 96)
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 38))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text("没有打开的页面")
                            .font(.title3.weight(.semibold))
                        Text("回到主页点书签，就能在这里切换多个页面")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            pendingTop = nil; pendingTopPage = nil
                            wm.goHome()
                            dismissAfter { }
                        } label: {
                            Label("新建页面", systemImage: "plus")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                                 onClose: { wm.closePage(page.id) },
                                                 onEdit: { editingBookmark = page.bookmark },
                                                 onTimeLimit: { timeLimitBookmark = page.bookmark })
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
            .sheet(item: $editingBookmark) { bm in
                BookmarkEditView(store: store, bookmark: bm)
            }
            .sheet(item: $timeLimitBookmark) { bm in
                NavigationStack {
                    TimeLimitSettingsView(store: store, bookmark: bm)
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
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground).opacity(0.5))
                    .frame(width: 170, height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .foregroundStyle(.secondary.opacity(0.7))
                    )
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                Text("新开页面")
                    .font(.subheadline.weight(.medium))
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
    let onEdit: () -> Void
    let onTimeLimit: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var cardColors: [Color] {
        CardPalette.resolvedGradient(for: page.bookmark)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = page.snapshot {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        // 占位：书签同色渐变 + 名称首字，跟主页卡片呼应
                        LinearGradient(colors: cardColors, startPoint: .top, endPoint: .bottom)
                            .overlay {
                                Text(String(page.bookmark.name.prefix(1)))
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .frame(width: 170, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // 抬升投影（iOS 后台卡片质感），不用 hairline 灰描边
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(isPending ? Color.accentColor : .clear, lineWidth: isPending ? 3 : 0)
                )
                .overlay(alignment: .topLeading) {
                    if isPending {
                        Text("分屏上半")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
            }

            // 时间信息（设了限时的书签才显示）：已用/限额 + 进度条
            if page.bookmark.timeLimitEnabled {
                UsageBadge(bookmark: page.bookmark)
                    .frame(width: 170)
            }

            Text(page.pageTitle.isEmpty ? page.bookmark.name : page.pageTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(width: 170)
        }
        .offset(y: dragOffset)
        .opacity(dragOffset < 0 ? CGFloat(1) + dragOffset / CGFloat(400) : CGFloat(1))   // 上滑逐渐淡出
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // 长按出现操作：分屏（关闭改上滑手势）
        .contextMenu {
            Button {
                onSplit()
            } label: {
                Label(isPending ? "取消分屏" : "分屏", systemImage: "rectangle.split.2x1")
            }
            Button {
                onEdit()
            } label: {
                Label("编辑书签", systemImage: "pencil")
            }
            Button {
                onTimeLimit()
            } label: {
                Label(page.bookmark.timeLimitEnabled ? "使用时间设置" : "设置使用时间", systemImage: "hourglass")
            }
        }
        // 上滑关闭（类 iOS 后台卡片）：跟手拖动，越过阈值松手关闭
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { v in
                    if v.translation.height < 0 { dragOffset = v.translation.height }
                }
                .onEnded { v in
                    if v.translation.height < -80 {
                        withAnimation(.easeOut(duration: 0.15)) { dragOffset = -400 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onClose() }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragOffset = 0 }
                    }
                }
        )
    }
}
