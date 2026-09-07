import Foundation

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "https://"
    var icon: String = "🌐"
    var scale: Double = 1.0        // 页面缩放 0.5 - 3.0
    var fontAdjust: Double = 0     // 文字大小偏移百分比 -50 ~ +100
    var desktopUA: Bool = false    // 桌面 UA
    var basicAuthUser: String = "" // HTTP Basic Auth 用户名（空 = 不启用）
    var basicAuthPass: String = "" // HTTP Basic Auth 密码
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

    // MARK: - 导出 / 导入

    /// 导出当前书签到临时 json 文件（供分享面板使用），返回文件 URL
    func exportURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-bookmarks.json")
        try? JSONEncoder().encode(bookmarks).write(to: url, options: .atomic)
        return url
    }

    /// 从 json 导入书签，按 id 去重合并。返回新增数量，-1 = 解析失败
    func importFrom(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return -1
        }
        var existing = Set(bookmarks.map(\.id))
        var added = 0
        for bm in imported where !existing.contains(bm.id) {
            bookmarks.append(bm)
            existing.insert(bm.id)
            added += 1
        }
        return added
    }
}
