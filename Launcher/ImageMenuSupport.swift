import UIKit
import WebKit

// MARK: - 网页长按菜单（图片：分享/存储/拷链接；普通链接：打开/拷贝/分享链接）
//
// 背景：WKWebView 默认长按图片只有「存储图像」，而 App 没声明相册权限时该动作静默失败，
// 也没法直接把图分享到微信/QQ 等其他 App。
// 做法：挂 WKUIDelegate 自定义长按菜单。⚠️ iOS 上这个方法一旦实现，completionHandler(nil)
// = 完全不弹菜单（WebKit 头文件原文："pass nil to not show a context menu"），不是"保持系统默认"，
// 所以必须自己兜住原来的菜单，否则普通链接会变成长按没反应：
//   ① 图片（链接是图片 / 整页就是一张图 / 链接命中页面里的 <img>）→ 图片菜单
//   ② 普通链接 → 等价系统默认的菜单（打开链接 / 拷贝链接 / 分享链接）
//   ③ 都不是（长按文本等）→ nil（系统默认本来就不弹，无回归）
// 分享走 UIActivityViewController（系统分享面板），不需要相册权限；
// 「存储图像」需要 Info.plist 的 NSPhotoLibraryAddUsageDescription（project.yml 已补），失败会给提示。

final class WebViewContextMenuDelegate: NSObject, WKUIDelegate {
    static let shared = WebViewContextMenuDelegate()

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    func webView(_ webView: WKWebView,
                 contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        let linkURL = elementInfo.linkURL
        // 交给页面判断：整页是不是一张图（直接打开图片链接的情况）；
        // 以及被长按的链接是否命中页面里某个 <img>（图片 URL 不带扩展名时靠这条兜住）
        let js = Self.imageProbeJS(link: linkURL?.absoluteString ?? "")
        webView.evaluateJavaScript(js) { res, _ in
            let probed = (res as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            let imageURL: URL? = probed ?? (linkURL.flatMap { Self.isImageURL($0) ? $0 : nil })

            if let imageURL {
                completionHandler(Self.imageMenu(imageURL: imageURL, webView: webView))
            } else if let link = linkURL {
                completionHandler(Self.linkMenu(url: link, webView: webView))
            } else {
                completionHandler(nil)
            }
        }
    }

    /// 探测 JS：返回图片地址（无则空串）
    private static func imageProbeJS(link: String) -> String {
        let lit = (try? JSONEncoder().encode(link)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function(){
          var link = \(lit);
          var b = document.body ? document.body.firstElementChild : null;
          if (b && b.tagName === 'IMG') { return b.currentSrc || b.src || ''; }
          if (link) {
            var imgs = document.images || [];
            for (var i = 0; i < imgs.length; i++) {
              var s = imgs[i].currentSrc || imgs[i].src;
              if (s && s === link) { return s; }
            }
          }
          return '';
        })();
        """
    }

    private static func isImageURL(_ u: URL) -> Bool {
        imageExts.contains(u.pathExtension.lowercased())
    }

    // MARK: 图片菜单
    private static func imageMenu(imageURL: URL, webView: WKWebView) -> UIContextMenuConfiguration {
        let ua = webView.customUserAgent
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "分享图像", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    shareImage(url: imageURL, userAgent: ua)
                },
                UIAction(title: "存储图像", image: UIImage(systemName: "square.and.arrow.down")) { _ in
                    downloadImage(url: imageURL, userAgent: ua) { img in
                        guard let img else { showToast("图片下载失败"); return }
                        PhotoSaver.shared.save(img)
                    }
                },
                UIAction(title: "拷贝图片链接", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.string = imageURL.absoluteString
                }
            ])
        }
    }

    // MARK: 普通链接菜单（等价系统默认，避免 completionHandler(nil) 把菜单整个干掉）
    private static func linkMenu(url: URL, webView: WKWebView) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "打开链接", image: UIImage(systemName: "arrow.up.right")) { _ in
                    webView.load(URLRequest(url: url))
                },
                UIAction(title: "拷贝链接", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: "分享链接", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    shareItems([url.absoluteString])
                }
            ])
        }
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

    // MARK: 拉起系统分享面板（图片下载失败时退化为分享链接）
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

    /// 轻提示（存图失败/无权限时告诉老板，而不是静默没反应）
    static func showToast(_ msg: String) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        top.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { alert.dismiss(animated: true) }
    }
}

/// 存相册：需要 Info.plist 的 NSPhotoLibraryAddUsageDescription 才会弹授权。
/// 首次调用由系统弹「允许访问相册」，用户拒绝则回调 error，这里给提示，不再静默失败。
private final class PhotoSaver: NSObject {
    static let shared = PhotoSaver()
    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self,
                                       #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error {
            WebViewContextMenuDelegate.showToast("存储失败：请在系统设置里允许 Launcher 访问相册")
            print("[Launcher] save image failed: \(error.localizedDescription)")
        }
    }
}
