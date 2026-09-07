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
