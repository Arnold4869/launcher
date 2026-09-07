import SwiftUI

@main
struct LauncherApp: App {
    @StateObject private var store = BookmarkStore()
    @StateObject private var wm = WindowManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                    .environmentObject(store)
                    .environmentObject(wm)

                // 全屏层（ZStack 自绘，fullScreen 变化直接切换）
                if let bm = wm.fullScreen {
                    WebFullScreenView(bookmark: bm)
                        .environmentObject(store)
                        .environmentObject(wm)
                        .transition(.opacity)
                }

                // 悬浮窗（最顶层，主页和全屏页都可见可点）
                if wm.floating != nil {
                    FloatingWindowView(wm: wm)
                        .allowsHitTesting(true)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: wm.fullScreen?.id)
        }
    }
}
