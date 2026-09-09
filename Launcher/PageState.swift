import Foundation
import WebKit
import UIKit

/// 一个打开的页面（常驻 WebView，最多 4 个）
/// webView 实例缓存在这里：SwiftUI 视图树卸载只把它从父视图摘下，实例由本类强持有不销毁，
/// 后台/全屏/分屏之间切换 = 同一 WKWebView 在不同容器间搬移，浏览状态全程保留。
final class PageState: Identifiable {
    let id = UUID()
    let bookmark: Bookmark
    /// 多任务卡片实时缩略图（didFinish 导航后刷新）
    @Published var snapshot: UIImage? = nil
    /// 当前网页标题（快照下的小字）
    @Published var pageTitle: String = ""
    private(set) lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }()
    init(_ bm: Bookmark) { self.bookmark = bm }

    /// 抓当前画面到缩略图（多任务卡片用）
    func captureSnapshot() {
        guard webView.frame.width > 0 else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, let image else { return }
            DispatchQueue.main.async {
                self.snapshot = image
                self.pageTitle = self.webView.title ?? ""
            }
        }
    }
}
