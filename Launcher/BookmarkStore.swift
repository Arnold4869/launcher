import SwiftUI

/// 柔和渐变色板：卡片随机取色
enum CardPalette {
    static let gradients: [[Color]] = [
        [Color(red: 0.55, green: 0.83, blue: 0.75), Color(red: 0.30, green: 0.66, blue: 0.60)],   // 薄荷绿
        [Color(red: 0.60, green: 0.78, blue: 0.95), Color(red: 0.35, green: 0.55, blue: 0.85)],   // 天蓝
        [Color(red: 0.98, green: 0.80, blue: 0.60), Color(red: 0.93, green: 0.60, blue: 0.40)],   // 暖橙
        [Color(red: 0.80, green: 0.72, blue: 0.95), Color(red: 0.60, green: 0.50, blue: 0.85)],   // 淡紫
        [Color(red: 0.97, green: 0.75, blue: 0.80), Color(red: 0.90, green: 0.55, blue: 0.62)],   // 粉红
        [Color(red: 0.95, green: 0.90, blue: 0.65), Color(red: 0.88, green: 0.78, blue: 0.45)],   // 鹅黄
        [Color(red: 0.65, green: 0.80, blue: 0.90), Color(red: 0.45, green: 0.65, blue: 0.82)],   // 雾蓝
        [Color(red: 0.72, green: 0.88, blue: 0.65), Color(red: 0.52, green: 0.74, blue: 0.45)],   // 草绿
        [Color(red: 0.85, green: 0.80, blue: 0.72), Color(red: 0.70, green: 0.62, blue: 0.52)],   // 米棕
        [Color(red: 0.70, green: 0.68, blue: 0.92), Color(red: 0.52, green: 0.55, blue: 0.85)],   // 蓝紫
        [Color(red: 0.95, green: 0.70, blue: 0.65), Color(red: 0.85, green: 0.50, blue: 0.48)],   // 珊瑚
        [Color(red: 0.62, green: 0.85, blue: 0.85), Color(red: 0.40, green: 0.70, blue: 0.72)]    // 青碧
    ]

    static func colors(for index: Int) -> [Color] {
        gradients[abs(index) % gradients.count]
    }

    static func randomIndex() -> Int {
        Int.random(in: 0..<gradients.count)
    }
}

/// 每行列数（全局设置，持久化到 UserDefaults）
enum GridSettings {
    @AppStorage("gridColumns") static var columns: Int = 2
}

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "https://"
    var icon: String = "🌐"        // 旧字段保留兼容，界面已不用
    var colorIndex: Int = CardPalette.randomIndex()
    var scale: Double = 1.0        // 页面缩放 0.5 - 3.0
    var fontAdjust: Double = 0     // 文字大小偏移百分比 -50 ~ +100
    var desktopUA: Bool = false    // 桌面 UA
    var basicAuthUser: String = "" // HTTP Basic Auth 用户名（空 = 不启用）
    var basicAuthPass: String = "" // HTTP Basic Auth 密码
    var loginUser: String = ""     // 网页登录表单自动填充用户名（空 = 不启用）
    var loginPass: String = ""     // 网页登录表单自动填充密码
    var autoSubmit: Bool = true    // 自动填充后自动提交登录（回车/点登录钮）

    // 自定义解码：旧 json 缺新字段时用默认值，避免 decode 整体失败丢书签
    init(id: UUID = UUID(), name: String = "", urlString: String = "https://", icon: String = "🌐",
         colorIndex: Int = CardPalette.randomIndex(), scale: Double = 1.0, fontAdjust: Double = 0,
         desktopUA: Bool = false, basicAuthUser: String = "", basicAuthPass: String = "",
         loginUser: String = "", loginPass: String = "", autoSubmit: Bool = true) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.icon = icon
        self.colorIndex = colorIndex
        self.scale = scale
        self.fontAdjust = fontAdjust
        self.desktopUA = desktopUA
        self.basicAuthUser = basicAuthUser
        self.basicAuthPass = basicAuthPass
        self.loginUser = loginUser
        self.loginPass = loginPass
        self.autoSubmit = autoSubmit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString) ?? "https://"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "🌐"
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? CardPalette.randomIndex()
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        fontAdjust = try c.decodeIfPresent(Double.self, forKey: .fontAdjust) ?? 0
        desktopUA = try c.decodeIfPresent(Bool.self, forKey: .desktopUA) ?? false
        basicAuthUser = try c.decodeIfPresent(String.self, forKey: .basicAuthUser) ?? ""
        basicAuthPass = try c.decodeIfPresent(String.self, forKey: .basicAuthPass) ?? ""
        loginUser = try c.decodeIfPresent(String.self, forKey: .loginUser) ?? ""
        loginPass = try c.decodeIfPresent(String.self, forKey: .loginPass) ?? ""
        autoSubmit = try c.decodeIfPresent(Bool.self, forKey: .autoSubmit) ?? true
    }
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
