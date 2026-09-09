import SwiftUI

// MARK: - 多任务切换器（类浏览器标签页管理）
//
// 列出所有常驻后台页面（WebView 不重建，浏览状态保留）：
// - 点卡片 = 切到该页（全屏）
// - × = 关闭该页
// - 「分屏」= 把该页设为分屏半屏（第一页设后不关闭，选第二页时两半齐自动进分屏；
//   若已有一半在等待，直接点另一页 = 补齐进分屏）

struct TaskSwitcherView: View {
    @EnvironmentObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    /// 待配对的第一半（选了上半屏等待下半屏时非 nil）
    @State private var pendingTop: Bookmark?

    var body: some View {
        NavigationStack {
            Group {
                if wm.pages.isEmpty {
                    VStack(spacing: 12) {
                        Text("🗂").font(.system(size: 56))
                        Text("没有打开的页面")
                            .foregroundStyle(.secondary)
                        Text("从主屏点开书签后，这里会显示后台页面")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        if pendingTop != nil {
                            Section {
                                HStack {
                                    Image(systemName: "rectangle.split.2x1")
                                        .foregroundStyle(.blue)
                                    Text("已选「\(pendingTop!.name)」为上半屏，点下面任一页面补齐下半屏")
                                        .font(.footnote)
                                }
                            }
                        }
                        Section("打开的页面 (\(wm.pages.count))") {
                            ForEach(wm.pages) { page in
                                row(for: page)
                            }
                        }
                    }
                }
            }
            .navigationTitle("多任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for page: PageState) -> some View {
        let isActive = page.id == wm.fullscreenID
        let isPending = pendingTop?.id == page.bookmark.id
        HStack(spacing: 12) {
            // 缩略色块（书签渐变色 + 名称首字，点卡片主体 = 切换/配对）
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: CardPalette.colors(for: page.bookmark.colorIndex),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .brightness(-0.18)
                Text(String(page.bookmark.name.prefix(1)))
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(page.bookmark.name)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                Text(page.bookmark.urlString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Text("当前")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            }

            // 分屏按钮：pendingTop 为 nil → 设为上半屏等待配对；否则补为下半屏
            Button {
                handleSplitTap(page.bookmark)
            } label: {
                Image(systemName: isPending ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            // 关闭
            Button {
                withAnimation { wm.closePage(page.id) }
                if pendingTop?.id == page.bookmark.id { pendingTop = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleMainTap(page) }
    }

    private func handleMainTap(_ page: PageState) {
        if let top = pendingTop {
            // 已有上半屏在等待 → 这个页面补为下半屏，进分屏
            guard page.bookmark.id != top.id else { pendingTop = nil; return }
            wm.setPageForSplit(top, top: true)
            wm.setPageForSplit(page.bookmark, top: false)
            pendingTop = nil
            // 回主页再进分屏：不清 fullscreenID 会残留全屏层盖住分屏
            wm.goHome()
            dismiss()
        } else {
            wm.fullscreenID = page.id
            dismiss()
        }
    }

    private func handleSplitTap(_ bm: Bookmark) {
        if let top = pendingTop {
            guard bm.id != top.id else { return }
            wm.setPageForSplit(top, top: true)
            wm.setPageForSplit(bm, top: false)
            pendingTop = nil
            wm.goHome()
            dismiss()
        } else {
            pendingTop = bm
        }
    }
}
