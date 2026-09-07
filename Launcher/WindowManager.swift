import SwiftUI

/// 一个打开的页面（常驻 WebView，最多 2 个）
final class PageState: Identifiable {
    let id = UUID()
    let bookmark: Bookmark
    init(_ bm: Bookmark) { self.bookmark = bm }
}

final class WindowManager: ObservableObject {
    @Published var pages: [PageState] = []
    @Published var fullscreenID: UUID?
    @Published var floatingID: UUID?
    @Published var floatingPos: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 90, y: 120)
    @Published var floatingWidth: CGFloat = 110
    @Published var floatingHeight: CGFloat = 130

    /// 打开书签：已在列表里 → 直接放大到全屏；否则新开（超过 2 个关掉悬浮那个）
    func open(_ bm: Bookmark) {
        if let page = pages.first(where: { $0.bookmark.id == bm.id }) {
            fullscreenID = page.id
            return
        }
        if pages.count >= 2 {
            if let fid = floatingID {
                pages.removeAll { $0.id == fid }
            } else if let oldest = pages.first {
                pages.removeAll { $0.id == oldest.id }
            }
        }
        let page = PageState(bm)
        pages.append(page)
        fullscreenID = page.id
    }

    /// 回主页：只关全屏层，页面状态保留
    func goHome() {
        fullscreenID = nil
    }

    /// 当前全屏页缩成悬浮窗（唯一入口，手动触发）
    func minimizeToFloating() {
        guard let fs = fullscreenID else { return }
        if let fid = floatingID {
            pages.removeAll { $0.id == fid }   // 只允许一个悬浮窗
        }
        floatingID = fs
        fullscreenID = nil
    }

    /// 点悬浮窗：全屏 ↔ 悬浮互换（WebView 不重建，浏览状态保留）
    func swap() {
        let f = floatingID
        floatingID = fullscreenID
        fullscreenID = f
    }

    func closePage(_ id: UUID) {
        pages.removeAll { $0.id == id }
        if fullscreenID == id { fullscreenID = nil }
        if floatingID == id { floatingID = nil }
    }
}
