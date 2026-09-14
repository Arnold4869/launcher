import UIKit
import WebKit

// MARK: - 访问标识（User-Agent）三档
//
// 书签的 uaMode：0 = iOS 默认（不设 customUserAgent，用系统 Safari UA）
//                1 = Android 手机 UA
//                2 = PC 桌面 UA（Mac Safari，桌面版网页）
// legacy 字段 desktopUA 仅作兼容读写：uaMode=2 时同步置 true，旧 json 里 desktopUA=true 会反解成 uaMode=2。

enum UserAgentOption {
    static let titles = ["iOS 默认", "Android", "PC 桌面"]
    static let shortTitles = ["iOS", "Android", "PC"]

    static let androidUA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    /// customUserAgent 该设的值；nil = 系统默认（iOS Safari）
    static func value(for mode: Int) -> String? {
        switch mode {
        case 1: return androidUA
        case 2: return desktopUA
        default: return nil
        }
    }

    static func title(for mode: Int) -> String {
        (mode >= 0 && mode < titles.count) ? titles[mode] : titles[0]
    }

    static func shortTitle(for mode: Int) -> String {
        (mode >= 0 && mode < shortTitles.count) ? shortTitles[mode] : shortTitles[0]
    }
}

extension WKWebView {
    /// 切换访问标识：值真的变了才写 + reload（否则每次视图重绘都白刷一次页面）
    func applyUAMode(_ mode: Int) {
        let want = UserAgentOption.value(for: mode)
        guard customUserAgent != want else { return }
        customUserAgent = want
        reload()
    }
}
