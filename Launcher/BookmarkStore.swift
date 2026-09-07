import Foundation

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "https://"
    var icon: String = "🌐"
    var scale: Double = 1.0        // 页面缩放 0.5 - 3.0
    var fontAdjust: Double = 0     // 文字大小偏移百分比 -50 ~ +100
    var desktopUA: Bool = false    // 桌面 UA
}

final class BookmarkStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = [] {
        didSet { save() }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("bookmarks.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
