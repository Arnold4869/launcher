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
    /// 常驻 WebView：被释放后下次访问自动重建（重新加载该页）
    var webView: WKWebView {
        if let heldWebView { return heldWebView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        heldWebView = wv
        released = false
        return wv
    }
    init(_ bm: Bookmark) { self.bookmark = bm }

    /// 内存紧张时释放后台页的 WebView（保留页面记录与缩略图，切回来时重新加载）
    /// 目的：避免前台正在阅读的页面被系统回收进程，出现"突然刷新/白屏"
    func releaseWebView() {
        guard !released else { return }
        released = true
        let wv = heldWebView
        heldWebView = nil
        wv?.stopLoading()
        wv?.navigationDelegate = nil
        wv?.removeFromSuperview()
        wv?.loadHTMLString("", baseURL: nil)
    }

    /// 是否已释放（下次访问 WebView 时重建并重载）
    private(set) var released = false
    private var heldWebView: WKWebView?

    /// 抓当前画面到缩略图（多任务卡片用）
    /// 正在前台全屏显示时不抓快照：截图会占用主线程，阅读翻页时可能被看成"刷一下"
    var snapshotSuspended = false

    func captureSnapshot() {
        guard webView.frame.width > 0, !snapshotSuspended else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, let image else { return }
            DispatchQueue.main.async {
                self.snapshot = image
                self.pageTitle = self.webView.title ?? ""
            }
        }
    }
}
