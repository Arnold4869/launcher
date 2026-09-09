import Foundation
import WebKit

/// 一个打开的页面（常驻 WebView，最多 4 个）
/// webView 实例缓存在这里：SwiftUI 视图树卸载只把它从父视图摘下，实例由本类强持有不销毁，
/// 后台/全屏/分屏之间切换 = 同一 WKWebView 在不同容器间搬移，浏览状态全程保留。
final class PageState: Identifiable {
    let id = UUID()
    let bookmark: Bookmark
    private(set) lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }()
    init(_ bm: Bookmark) { self.bookmark = bm }
}
