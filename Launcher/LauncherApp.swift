import SwiftUI

@main
struct LauncherApp: App {
    @StateObject private var store = BookmarkStore()
    @StateObject private var wm = WindowManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                home
                pageLayer
            }
            .animation(.easeInOut(duration: 0.2), value: wm.fullscreenID)
            .animation(.easeInOut(duration: 0.2), value: wm.floatingID)
        }
    }

    private var home: some View {
        HomeView()
            .environmentObject(store)
            .environmentObject(wm)
    }

    private var pageLayer: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(wm.pages) { page in
                    PageHost(page: page, wm: wm, geo: geo)
                        .environmentObject(store)
                        .zIndex(page.id == wm.floatingID ? 2 : 1)
                }

                if let top = wm.splitTop, let bottom = wm.splitBottom {
                    SplitViewScreen(top: top, bottom: bottom,
                                    topPage: wm.splitTopPage, bottomPage: wm.splitBottomPage)
                        .environmentObject(wm)
                        .environmentObject(store)
                        .zIndex(3)
                }
            }
        }
        .ignoresSafeArea()
    }
}
