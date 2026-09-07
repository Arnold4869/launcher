import SwiftUI

@main
struct LauncherApp: App {
    @StateObject private var store = BookmarkStore()
    @State private var splitPair: SplitPair?

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: .openSplit)) { note in
                    splitPair = note.object as? SplitPair
                }
                .fullScreenCover(item: $splitPair) { pair in
                    SplitViewScreen(top: pair.top, bottom: pair.bottom)
                }
        }
    }
}
