import SwiftUI

/// 全屏/悬浮窗口状态管理（App 级）
final class WindowManager: ObservableObject {
    @Published var fullScreen: Bookmark?   // 当前全屏打开的书签
    @Published var floating: Bookmark?     // 悬浮窗里的书签

    func open(_ bm: Bookmark) {
        fullScreen = bm
    }

    /// 主页：真正关闭全屏页（悬浮窗保留不动）
    func goHome() {
        fullScreen = nil
    }

    /// 当前全屏页缩成悬浮窗，回主页
    func minimizeCurrentToFloating() {
        guard let cur = fullScreen else { return }
        floating = cur
        fullScreen = nil
    }

    /// 点悬浮窗：与当前全屏互换；主页时直接放大悬浮窗
    func tapFloating() {
        let f = floating
        floating = fullScreen
        fullScreen = f
    }

    func closeAll() {
        fullScreen = nil
        floating = nil
    }
}
