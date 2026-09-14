import SwiftUI

/// 柔和渐变色板：卡片随机取色
enum CardPalette {
    // iOS 系统色深变体：同色相渐变（顶亮底暗），像 iOS 主屏 app 图标，非跨色相糖果渐变
    static let gradients: [[Color]] = [
        [Color(red: 0.30, green: 0.53, blue: 0.98), Color(red: 0.14, green: 0.35, blue: 0.82)],  // 蓝 (systemBlue)
        [Color(red: 0.25, green: 0.78, blue: 0.35), Color(red: 0.12, green: 0.55, blue: 0.22)],  // 绿 (systemGreen)
        [Color(red: 1.00, green: 0.63, blue: 0.04), Color(red: 0.85, green: 0.45, blue: 0.02)],  // 橙 (systemOrange)
        [Color(red: 1.00, green: 0.38, blue: 0.51), Color(red: 0.85, green: 0.21, blue: 0.33)],  // 粉 (systemPink)
        [Color(red: 0.70, green: 0.32, blue: 0.87), Color(red: 0.50, green: 0.19, blue: 0.70)],  // 紫 (systemPurple)
        [Color(red: 0.20, green: 0.68, blue: 0.90), Color(red: 0.08, green: 0.49, blue: 0.71)]   // 青 (systemTeal)
    ]

    static func colors(for index: Int) -> [Color] {
        gradients[abs(index) % gradients.count]
    }

    static func randomIndex() -> Int {
        Int.random(in: 0..<gradients.count)
    }

    /// 由任意主色 hex 生成同色相渐变（顶亮底暗）——图标取色/自定义取色共用
    static func gradient(fromHex hex: String) -> [Color]? {
        autoGradient(fromHex: hex)
    }

    static func autoGradient(fromHex hex: String) -> [Color]? {
        guard let base = UIColor(hex: hex) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        guard base.getHue(&h, saturation: &s, brightness: &br, alpha: &a) else { return nil }
        // 顶：提亮；底：压暗，保持同色相
        let top = UIColor(hue: h, saturation: min(s * 0.85, 1), brightness: min(br * 1.15, 1), alpha: 1)
        let bottom = UIColor(hue: h, saturation: min(s * 1.0, 1), brightness: max(br * 0.65, 0.2), alpha: 1)
        return [Color(top), Color(bottom)]
    }

    // 渐变解析缓存：旧手机滚动书签网格时每帧重算 getHue 是浪费。
    // 键 = colorMode|hex|colorIndex，值 = 渐变数组（Color 是轻量值类型，缓存安全）。
    private static var gradientCache: [String: [Color]] = [:]

    /// 按书签的 colorMode 解析卡片渐变（BookmarkCard 唯一入口，带缓存）
    static func resolvedGradient(for bm: Bookmark) -> [Color] {
        let key: String
        switch bm.colorMode {
        case 1: key = "1|\(bm.autoColorHex)"
        case 2: key = "2|\(bm.customColorHex)"
        default: key = "0|\(bm.colorIndex)"
        }
        if let hit = gradientCache[key] { return hit }
        let g: [Color]
        switch bm.colorMode {
        case 1: g = autoGradient(fromHex: bm.autoColorHex) ?? colors(for: bm.colorIndex)
        case 2: g = autoGradient(fromHex: bm.customColorHex) ?? colors(for: bm.colorIndex)
        default: g = colors(for: bm.colorIndex)
        }
        gradientCache[key] = g
        return g
    }
}

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "https://"
    var icon: String = "🌐"        // 旧字段保留兼容，界面已不用
    var colorIndex: Int = CardPalette.randomIndex()
    var scale: Double = 1.0        // 页面缩放 0.5 - 3.0
    var fontAdjust: Double = 0     // 文字大小偏移百分比 -50 ~ +100
    var desktopUA: Bool = false    // 桌面 UA（legacy，兼容旧 json；uaMode=2 时同步置 true）
    var uaMode: Int = 0            // 访问标识 0=iOS默认 1=Android 2=PC桌面
    var basicAuthUser: String = "" // HTTP Basic Auth 用户名（空 = 不启用）
    var basicAuthPass: String = "" // HTTP Basic Auth 密码
    var loginUser: String = ""     // 网页登录表单自动填充用户名（空 = 不启用）
    var loginPass: String = ""     // 网页登录表单自动填充密码
    var autoSubmit: Bool = true    // 自动填充后自动提交登录（回车/点登录钮）
    var colorMode: Int = 0          // 0=随机色 1=图标取色 2=自定义取色
    var autoColorHex: String = ""  // 图标取色：提取到的品牌主色（RRGGBB）
    var customColorHex: String = "" // 自定义取色：用户选的颜色（RRGGBB）
    var timeLimitEnabled: Bool = false   // 每日限时开关
    var dailyLimitMinutes: Int = 30      // 每日限额（分钟）
    var unlockMode: Int = 0              // 解锁后：0=清零重来 1=今天不再锁 2=加时
    var unlockBonusMinutes: Int = 15     // 解锁后加时分钟数（unlockMode=2 时用）

    // 自定义解码：旧 json 缺新字段时用默认值，避免 decode 整体失败丢书签
    init(id: UUID = UUID(), name: String = "", urlString: String = "https://", icon: String = "🌐",
         colorIndex: Int = CardPalette.randomIndex(), scale: Double = 1.0, fontAdjust: Double = 0,
         desktopUA: Bool = false, basicAuthUser: String = "", basicAuthPass: String = "",
         loginUser: String = "", loginPass: String = "", autoSubmit: Bool = true,
         uaMode: Int = 0,
         colorMode: Int = 0, autoColorHex: String = "", customColorHex: String = "",
         timeLimitEnabled: Bool = false, dailyLimitMinutes: Int = 30, unlockMode: Int = 0,
         unlockBonusMinutes: Int = 15) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.icon = icon
        self.colorIndex = colorIndex
        self.scale = scale
        self.fontAdjust = fontAdjust
        self.desktopUA = desktopUA
        self.uaMode = uaMode
        self.basicAuthUser = basicAuthUser
        self.basicAuthPass = basicAuthPass
        self.loginUser = loginUser
        self.loginPass = loginPass
        self.autoSubmit = autoSubmit
        self.colorMode = colorMode
        self.autoColorHex = autoColorHex
        self.customColorHex = customColorHex
        self.timeLimitEnabled = timeLimitEnabled
        self.dailyLimitMinutes = dailyLimitMinutes
        self.unlockMode = unlockMode
        self.unlockBonusMinutes = unlockBonusMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, urlString, icon, colorIndex, scale, fontAdjust, desktopUA, uaMode
        case basicAuthUser, basicAuthPass, loginUser, loginPass, autoSubmit
        case colorMode, autoColorHex, customColorHex
        case timeLimitEnabled, dailyLimitMinutes, unlockMode, unlockBonusMinutes
        case autoColor   // legacy 1.6.0 字段，仅迁移用
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(urlString, forKey: .urlString)
        try c.encode(icon, forKey: .icon)
        try c.encode(colorIndex, forKey: .colorIndex)
        try c.encode(scale, forKey: .scale)
        try c.encode(fontAdjust, forKey: .fontAdjust)
        try c.encode(desktopUA, forKey: .desktopUA)
        try c.encode(uaMode, forKey: .uaMode)
        try c.encode(basicAuthUser, forKey: .basicAuthUser)
        try c.encode(basicAuthPass, forKey: .basicAuthPass)
        try c.encode(loginUser, forKey: .loginUser)
        try c.encode(loginPass, forKey: .loginPass)
        try c.encode(autoSubmit, forKey: .autoSubmit)
        try c.encode(colorMode, forKey: .colorMode)
        try c.encode(autoColorHex, forKey: .autoColorHex)
        try c.encode(customColorHex, forKey: .customColorHex)
        try c.encode(timeLimitEnabled, forKey: .timeLimitEnabled)
        try c.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encode(unlockMode, forKey: .unlockMode)
        try c.encode(unlockBonusMinutes, forKey: .unlockBonusMinutes)
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
        uaMode = try c.decodeIfPresent(Int.self, forKey: .uaMode) ?? 0
        basicAuthUser = try c.decodeIfPresent(String.self, forKey: .basicAuthUser) ?? ""
        basicAuthPass = try c.decodeIfPresent(String.self, forKey: .basicAuthPass) ?? ""
        loginUser = try c.decodeIfPresent(String.self, forKey: .loginUser) ?? ""
        loginPass = try c.decodeIfPresent(String.self, forKey: .loginPass) ?? ""
        autoSubmit = try c.decodeIfPresent(Bool.self, forKey: .autoSubmit) ?? true
        colorMode = try c.decodeIfPresent(Int.self, forKey: .colorMode) ?? 0
        autoColorHex = try c.decodeIfPresent(String.self, forKey: .autoColorHex) ?? ""
        customColorHex = try c.decodeIfPresent(String.self, forKey: .customColorHex) ?? ""
        timeLimitEnabled = try c.decodeIfPresent(Bool.self, forKey: .timeLimitEnabled) ?? false
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes) ?? 30
        unlockMode = try c.decodeIfPresent(Int.self, forKey: .unlockMode) ?? 0
        unlockBonusMinutes = try c.decodeIfPresent(Int.self, forKey: .unlockBonusMinutes) ?? 15
        // 兼容 1.6.0：旧字段 autoColor=true 视作图标取色
        if try c.decodeIfPresent(Bool.self, forKey: .autoColor) ?? false { colorMode = 1 }
        // 兼容旧版本：老书签只有 desktopUA=true → 映射成 uaMode=2（PC）
        if uaMode == 0 && desktopUA { uaMode = 2 }
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
        var merged = bookmarks
        for bm in imported where !existing.contains(bm.id) {
            merged.append(bm)
            existing.insert(bm.id)
            added += 1
        }
        if added > 0 {
            bookmarks = merged   // 一次性赋值，didSet 只写一次盘（导入 N 个不会写 N 次）
        }
        return added
    }
}
