import UIKit
import WebKit

// MARK: - 页面分享（底栏「更多」→「分享页面」）
//
// 为什么不用长按：2.3.0 走 WKUIDelegate.contextMenuConfigurationForElement 对纯图片根本不触发
// （WebKit WKContentViewInteraction.mm: 只有 isLink 才进这个回调）；2.3.1 改注入 JS 检测长按，
// 但【直接打开图片地址】时 WebKit 用的是内置图片文档，用户脚本不执行 → 纯图片场景仍然无效。
// 结论：长按这条路对纯图片不可靠，全部回退到系统默认行为，分享能力收进导航栏「更多」里，
// 由原生代码自己判断当前页是图片还是网页，自适应分享。

enum PageShare {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    /// 入口：优先用调用方给的页面 WebView，没给就在视图层级里找当前可见的那个（分屏上半屏等场景）
    static func shareCurrentPage(_ webView: WKWebView?) {
        guard let wv = webView ?? visibleWebView() else {
            showToast("没有可分享的页面")
            return
        }
        guard let url = wv.url ?? URL(string: wv.currentBookmark.urlString) else {
            showToast("拿不到当前页面地址")
            return
        }
        // ① 地址后缀就是图片 → 直接按图片分享
        if imageExts.contains(url.pathExtension.lowercased()) {
            shareImage(url: url, userAgent: wv.customUserAgent)
            return
        }
        // ② 后缀看不出来（无扩展名/带参数的图床）：问页面本身
        //    document.contentType 形如 image/jpeg；整页一张图的页面 WebKit 会把图包成 body 首个子元素
        wv.evaluateJavaScript(Self.imageProbeJS) { res, _ in
            if let s = res as? String, !s.isEmpty, let imgURL = URL(string: s) {
                shareImage(url: imgURL, userAgent: wv.customUserAgent)
            } else {
                // ③ 普通网页 → 分享网址
                shareItems([url.absoluteString])
            }
        }
    }

    private static let imageProbeJS = """
    (function(){
      try {
        var ct = (document.contentType || '').toLowerCase();
        var b = document.body && document.body.firstElementChild;
        var imgDoc = ct.indexOf('image/') === 0 || (b && b.tagName === 'IMG');
        if (!imgDoc) return '';
        var img = (document.images && document.images.length) ? document.images[0] : b;
        if (!img) return '';
        return img.currentSrc || img.src || '';
      } catch (e) { return ''; }
    })();
    """

    /// 视图层级里当前可见的 WKWebView：分屏上半屏优先（屏幕坐标 y 最小且尺寸正常）
    private static func visibleWebView() -> WKWebView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        var found: [(y: CGFloat, wv: WKWebView)] = []
        func walk(_ v: UIView) {
            if let wv = v as? WKWebView, !wv.isHidden, wv.alpha > 0.01,
               wv.bounds.width > 1, wv.bounds.height > 1 {
                let frame = wv.convert(wv.bounds, to: window)
                if frame.intersects(window.bounds) {
                    found.append((frame.minY, wv))
                }
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(window)
        return found.sorted { $0.y < $1.y }.first?.wv
    }

    // MARK: 下载（带上 WebView 的 cookie 和 UA，保证需要登录的图也能下）
    static func downloadImage(url: URL, userAgent: String?, done: @escaping (UIImage?) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
            var req = URLRequest(url: url)
            if let ua = userAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
            URLSession.shared.dataTask(with: req) { data, _, _ in
                let img = data.flatMap(UIImage.init(data:))
                DispatchQueue.main.async { done(img) }
            }.resume()
        }
    }

    /// 分享图片本体（下载失败退化为分享图片链接），不经过相册权限
    static func shareImage(url: URL, userAgent: String?) {
        downloadImage(url: url, userAgent: userAgent) { img in
            shareItems(img.map { [$0] } ?? [url.absoluteString])
        }
    }

    static func shareItems(_ items: [Any]) {
        guard let top = topViewController() else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    static func showToast(_ msg: String) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        top.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { alert.dismiss(animated: true) }
    }
}
