import SwiftUI

/// 全屏/悬浮窗口状态管理（App 级）
final class WindowManager: ObservableObject {
    @Published var pages: [PageState] = []
    @Published var fullscreenID: UUID?
    @Published var floatingID: UUID?
    /// 悬浮窗功能开关：代码保留，暂不显示
    @Published var showFloating = false
    /// 分屏状态（经悬浮钮「分屏」进入）
    @Published var splitTop: Bookmark?
    @Published var splitBottom: Bookmark?
    @Published var floatingPos: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 90, y: 160)
    @Published var floatingWidth: CGFloat = 120
    // 默认高宽比 = 屏幕比例
    @Published var floatingHeight: CGFloat = 120 * (UIScreen.main.bounds.height / UIScreen.main.bounds.width)

    /// 打开书签：已在列表里 → 直接放大到全屏；否则新开（超过 4 个关掉最早的未显示页）
    func open(_ bm: Bookmark) {
        if let page = pages.first(where: { $0.bookmark.id == bm.id }) {
            fullscreenID = page.id
            return
        }
        if pages.count >= 4 {
            if let victim = pages.first(where: { $0.id != fullscreenID && $0.id != floatingID }) {
                pages.removeAll { $0.id == victim.id }
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

    /// 把某后台页设为分屏一半：top=true 设为上半屏。已在分屏里则换掉那半
    func setPageForSplit(_ bm: Bookmark, top: Bool) {
        if top { splitTop = bm } else { splitBottom = bm }
    }

    /// 两半都齐 → true（供调用方判断能否直接进分屏）
    var splitReady: Bool { splitTop != nil && splitBottom != nil }
}
