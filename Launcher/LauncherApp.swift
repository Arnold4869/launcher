import SwiftUI

@main
struct LauncherApp: App {
    @StateObject private var store = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
