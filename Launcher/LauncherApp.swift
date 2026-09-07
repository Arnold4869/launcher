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

                // 页面层：每个 PageState 一个常驻 WebView，互换只改 frame/位置
                GeometryReader { geo in
                    ForEach(wm.pages) { page in
                        PageHost(page: page, wm: wm, geo: geo)
                            .environmentObject(store)
                            .zIndex(page.id == wm.floatingID ? 2 : 1)
                    }
                }
                .ignoresSafeArea()
            }
            .animation(.easeInOut(duration: 0.2), value: wm.fullscreenID)
            .animation(.easeInOut(duration: 0.2), value: wm.floatingID)
        }
    }
}
