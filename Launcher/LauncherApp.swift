import SwiftUI
import AVFoundation

@main
struct LauncherApp: App {
    @StateObject private var store = BookmarkStore()
    @StateObject private var wm = WindowManager()

    init() {
        // 视频站点（抖音等）：允许静音开关开着时也出声
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            // 忽略：拿不到音频会话也不影响网页加载
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                home
                pageLayer
            }
            .animation(.easeInOut(duration: 0.2), value: wm.fullscreenID)
            .onAppear {
                wm.restorePages(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                wm.releaseBackgroundWebViews()
            }
            .sheet(item: $wm.lockedBookmark) { bm in
                TimeLockUnlockView(bookmark: bm) { mode in
                    wm.applyUnlock(bm, mode: mode)
                }
            }
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
                        .environmentObject(wm)
                        .environmentObject(store)
                        .zIndex(1)
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
