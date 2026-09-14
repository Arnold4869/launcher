import UIKit
import WebKit

// MARK: - 页面分享 v2（2.5.0）
//
// 三种分享物，按当前页自适应：
//   • 当前页本身就是一张图（URL 后缀 / contentType / 整页一张图）→「分享图片」直接下载图本体分享
//   • 普通网页 →「分享页面截图」= 可见区域全分辨率 PNG（takeSnapshot，不降采样）
//              「分享页面 PDF」= WKWebView.createPDF 整页（官方 API，含全部已渲染内容）
//   • 任何情况都可「分享网址」
// 头文件名带书签名，微信/邮件里能看出是什么页面。

enum PageShare {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    /// 当前页是否为纯图片页（决定「分享页面」菜单项显示成「分享图片」）
    static func isImagePage(_ wv: WKWebView, done: @escaping (Bool) -> Void) {
        guard let url = wv.url else { done(false); return }
        if imageExts.contains(url.pathExtension.lowercased()) { done(true); return }
        wv.evaluateJavaScript(imageProbeJS) { res, _ in
            done((res as? String)?.isEmpty == false)
        }
    }

    /// 菜单项调用：图片页 → 分享图片本体；普通页 → 分享可见区域 PNG 截图
    static func shareDefault(_ wv: WKWebView) {
        isImagePage(wv) { isImg in
            if isImg {
                guard let url = wv.url else { shareVisibleSnapshot(wv); return }
                shareImage(url: url, userAgent: wv.customUserAgent, name: wv.currentBookmark.name)
            } else {
                shareVisibleSnapshot(wv)
            }
        }
    }

    // MARK: PNG 截图（可见区域，全分辨率）
    static func shareVisibleSnapshot(_ wv: WKWebView) {
        showWaiting("正在生成截图…")
        wv.takeSnapshot(with: nil) { image, _ in
            guard let img = image else {
                hideWaiting(); showToastLater("截图失败"); return
            }
            guard let png = img.pngData() else {
                hideWaiting(); showToastLater("PNG 编码失败"); return
            }
            let name = sanitizedFileName(wv.currentBookmark.name.isEmpty ? "页面截图" : wv.currentBookmark.name)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)-截图.png")
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                hideWaiting(); showToastLater("截图保存失败"); return
            }
            hideWaiting()
            // 等 HUD 消失再弹分享面板：iOS 不允许在 present 过程中叠 present
            shareItemsLater([url])
        }
    }

    // MARK: 整页 PDF（官方 createPDF；rect 留 nil = 整页，.zero 是 0×0 空白 PDF）
    static func shareFullPDF(_ wv: WKWebView) {
        showWaiting("正在生成 PDF…")
        wv.createPDF(configuration: WKPDFConfiguration()) { result in
            switch result {
            case .success(let data):
                let name = sanitizedFileName(wv.currentBookmark.name.isEmpty ? "页面" : wv.currentBookmark.name)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(name).pdf")
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    hideWaiting(); showToastLater("PDF 保存失败"); return
                }
                hideWaiting()
                shareItemsLater([url])
            case .failure:
                hideWaiting()
                showToastLater("PDF 生成失败")
            }
        }
    }

    /// 分享当前页的图片本体（图片页专用；拿不到 URL 时退化为截图分享，不崩）
    static func shareCurrentImage(_ wv: WKWebView) {
        guard let url = wv.url ?? URL(string: wv.currentBookmark.urlString) else {
            shareVisibleSnapshot(wv)
            return
        }
        shareImage(url: url, userAgent: wv.customUserAgent, name: wv.currentBookmark.name)
    }

    // MARK: 分享网址
    static func shareURL(_ wv: WKWebView) {
        guard let url = wv.url ?? URL(string: wv.currentBookmark.urlString) else {
            showToast("拿不到当前页面地址")
            return
        }
        shareItems([url.absoluteString])
    }

    // MARK: 复制网址
    static func copyURL(_ wv: WKWebView) {
        guard let url = wv.url ?? URL(string: wv.currentBookmark.urlString) else {
            showToast("拿不到当前页面地址")
            return
        }
        UIPasteboard.general.string = url.absoluteString
        showToast("已复制网址")
    }

    /// 当前显示的网址（面板地址栏用）
    static func displayURL(_ wv: WKWebView) -> String {
        wv.url?.absoluteString ?? wv.currentBookmark.urlString
    }

    // MARK: 内部

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

    /// 视图层级里当前可见的 WKWebView（分屏等场景无法直接拿到实例时分屏上半屏优先）
    static func visibleWebView() -> WKWebView? {
        let scenes = UIApplication.shared.connectedScenes
        let windows = scenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) else { return nil }
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

    /// 分享图片本体（带 WebView cookie + UA，登录站点也能下）；失败退化为分享图片链接
    static func shareImage(url: URL, userAgent: String?, name: String = "") {
        showWaiting("正在获取图片…")
        downloadImage(url: url, userAgent: userAgent) { img in
            hideWaiting()
            if let img {
                shareItemsLater([img])
            } else {
                shareItemsLater([url.absoluteString])
            }
        }
    }

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

    private static func sanitizedFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean = s.components(separatedBy: bad).joined(separator: " ")
        return String(clean.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 等待浮层（生成 PNG/PDF 可能要一两秒，给个反馈）
    //
    // ⚠️ 不能用 UIAlertController/任何 UIViewController.present：
    // dismiss 它之后立刻 present 分享面板 = iOS 拒绝（"attempt to present while presenting"），
    // 分享面板无声无息不出现 —— 这就是 2.5.0 分享"点了没反应"的根因之一。
    // 所以 HUD 用自绘 UIWindow，不占 present 栈。

    private static var hudWindow: UIWindow?
    private static var hudLabel: UILabel?

    private static func showWaiting(_ msg: String) {
        hideWaiting()
        let scenes = UIApplication.shared.connectedScenes
        guard let scene = scenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        w.layer.cornerRadius = 14
        w.bounds = CGRect(x: 0, y: 0, width: 170, height: 84)

        let label = UILabel()
        label.text = msg
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.frame = w.bounds
        w.addSubview(label)

        w.center = scene.windows.first?.center ?? CGPoint(x: 200, y: 400)
        // 只显示、不抢 key：抢 key 会干扰键盘/系统弹窗
        w.isHidden = false
        hudWindow = w
        hudLabel = label
    }

    private static func hideWaiting() {
        hudWindow?.isHidden = true
        hudWindow = nil
        hudLabel = nil
    }

    static func shareItems(_ items: [Any]) {
        guard let top = topViewController() else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    /// 分享面板延迟弹：确认 HUD 已消失、上一个 presentation 已收尾（iOS 不允许叠 present）
    static func shareItemsLater(_ items: [Any]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            shareItems(items)
        }
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

    /// toast 延迟弹：同样避开 present 冲突（hideWaiting 之后紧接 showToast 会互吃）
    static func showToastLater(_ msg: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showToast(msg)
        }
    }
}
