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

                // 悬浮窗（覆盖主页）
                if wm.floating != nil {
                    FloatingWindowView(wm: wm)
                        .allowsHitTesting(true)
                }
            }
            .fullScreenCover(item: $wm.fullScreen) { bm in
                WebFullScreenView(bookmark: bm)
                    .environmentObject(store)
                    .environmentObject(wm)
            }
        }
    }
}
