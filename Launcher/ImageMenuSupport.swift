import UIKit
import WebKit

// MARK: - 网页图片长按菜单（分享/存储/拷链接）+ 链接长按菜单兜底
//
// ⚠️ 关键限制（WebKit 源码 WKContentViewInteraction.mm L15534 实锤）：
// 公开委托 webView:contextMenuConfigurationForElement: 只在长按【链接】(isLink) 时才被调用；
// 纯图片 / 整页一张图 根本不触发它 → 走 WebKit 默认菜单。所以图片走另一条路：
//   注入 JS 检测长按命中 <img>（0.55s 未移动）→ messageHandler 回调原生弹菜单，
//   同时 CSS `-webkit-touch-callout:none` 关掉 WebKit 自带图片菜单避免双菜单
//   （源码 L3296/L15355：touchCalloutEnabled=false 时默认菜单直接不弹，这是官方开关）。
// 链接（含包在 <a> 里的图片）仍走 contextMenuConfigurationForElement（对链接有效），
// 且 iOS 上该方法返回 nil = 完全不弹菜单，必须自己补等价菜单，否则长按链接没反应。

final class WebViewContextMenuDelegate: NSObject, WKUIDelegate {
    static let shared = WebViewContextMenuDelegate()

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    // MARK: 链接长按菜单（此委托只对链接触发；纯图片走 JS 检测，见 WebViewLongPressImage）
    func webView(_ webView: WKWebView,
                 contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let link = elementInfo.linkURL else {
            completionHandler(nil)   // 非链接：系统默认本来就不弹，无回归
            return
        }
        // <a> 包着 <img> 的情况：链接地址命中页面里某张图 → 给图片菜单（能分享图片），
        // 否则只给链接菜单（打开/拷贝/分享）。probe 命中不到就退回链接菜单。
        webView.evaluateJavaScript(Self.imageProbeJS(link: link.absoluteString)) { res, _ in
            if let s = res as? String, !s.isEmpty, let imgURL = URL(string: s) {
                completionHandler(Self.imageMenu(imageURL: imgURL, webView: webView, fallbackLink: link))
            } else {
                completionHandler(Self.linkMenu(url: link, webView: webView))
            }
        }
    }

    /// 探测页面里是否有一张图对应给定链接地址（返回图片地址，无则空串）
    private static func imageProbeJS(link: String) -> String {
        let lit = (try? JSONEncoder().encode(link)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function(){
          var link = \(lit);
          var imgs = document.images || [];
          for (var i = 0; i < imgs.length; i++) {
            var s = imgs[i].currentSrc || imgs[i].src;
            if (s && s === link) { return s; }
          }
          return '';
        })();
        """
    }

    // MARK: 图片菜单（fallbackLink 非 nil = 这张图外面还包着链接，额外给打开/拷贝链接）
    private static func imageMenu(imageURL: URL, webView: WKWebView, fallbackLink: URL? = nil) -> UIContextMenuConfiguration {
        let ua = webView.customUserAgent
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var items: [UIMenuElement] = [
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
            ]
            if let link = fallbackLink {
                items.append(UIAction(title: "拷贝所在链接", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = link.absoluteString
                })
            }
            return UIMenu(title: "", children: items)
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

    static func showToast(_ msg: String) {
        guard let top = topViewController() else { return }
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        top.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { alert.dismiss(animated: true) }
    }
}

// MARK: - 图片长按：JS 检测 + 原生菜单（整页图片/纯 <img> 都覆盖，公开 API 不触发的地方靠它）

enum WebViewLongPressImage {
    /// WebView 创建时调用：注册 messageHandler + 注入检测脚本（所有新 WebView 都要过一遍）
    static func install(into config: WKWebViewConfiguration) {
        let uc = config.userContentController
        uc.add(ImageMenuBridge.shared, name: "launcherImageMenu")
        uc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }

    private static let js = """
    (function(){
      if (window.__launcherLPInstalled) return;
      window.__launcherLPInstalled = true;
      // 关掉 WebKit 自带图片长按菜单（touchCalloutEnabled=false 时不弹），避免和我们的菜单双弹
      var style = document.createElement('style');
      style.textContent = 'img{-webkit-touch-callout:none!important;-webkit-user-select:none!important}';
      (document.head || document.documentElement).appendChild(style);
      // 整页一张图的页面：连 body 的 callout 也关掉
      try {
        var b = document.body && document.body.firstElementChild;
        if (b && b.tagName === 'IMG') {
          var s2 = document.createElement('style');
          s2.textContent = 'body{-webkit-touch-callout:none!important}';
          (document.head || document.documentElement).appendChild(s2);
        }
      } catch(e) {}
      var timer = null, startPos = null, targetImg = null;
      function clear() { if (timer) { clearTimeout(timer); timer = null; } startPos = null; targetImg = null; }
      document.addEventListener('touchstart', function(e){
        clear();
        if (!e.touches || e.touches.length !== 1) return;
        var t = e.target;
        if (!t || !t.closest) return;
        var img = t.closest('img');
        if (!img) {
          // 整页一张图：WebKit 把图包成 body 第一个子元素，e.target 可能直接是 html
          var b = document.body && document.body.firstElementChild;
          if (b && b.tagName === 'IMG') img = b;
        }
        if (!img) return;
        if (img.closest('a')) return;   // 链接里的图走链接菜单（原生委托对链接有效）
        targetImg = img;
        startPos = { x: e.touches[0].clientX, y: e.touches[0].clientY };
        timer = setTimeout(function(){
          timer = null;
          if (!targetImg) return;
          var url = targetImg.currentSrc || targetImg.src;
          if (!url) return;
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.launcherImageMenu) {
            window.webkit.messageHandlers.launcherImageMenu.postMessage({ url: url });
          }
        }, 550);
      }, { passive: true });
      document.addEventListener('touchmove', function(e){
        if (!startPos || !timer || !e.touches || e.touches.length < 1) return;
        var dx = e.touches[0].clientX - startPos.x, dy = e.touches[0].clientY - startPos.y;
        if (dx * dx + dy * dy > 144) clear();   // 动了 12px 以上算滚动，不算长按
      }, { passive: true });
      document.addEventListener('touchend', clear, { passive: true });
      document.addEventListener('touchcancel', clear, { passive: true });
    })();
    """
}

final class ImageMenuBridge: NSObject, WKScriptMessageHandler {
    static let shared = ImageMenuBridge()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "launcherImageMenu",
              let body = message.body as? [String: Any],
              let s = body["url"] as? String,
              let url = URL(string: s) else { return }
        guard let top = WebViewContextMenuDelegate.topViewController() else { return }
        let ua = message.webView?.customUserAgent

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "分享图像", style: .default) { _ in
            WebViewContextMenuDelegate.shareImage(url: url, userAgent: ua)
        })
        alert.addAction(UIAlertAction(title: "存储图像", style: .default) { _ in
            WebViewContextMenuDelegate.downloadImage(url: url, userAgent: ua) { img in
                guard let img else {
                    WebViewContextMenuDelegate.showToast("图片下载失败")
                    return
                }
                PhotoSaver.shared.save(img)
            }
        })
        alert.addAction(UIAlertAction(title: "拷贝图片链接", style: .default) { _ in
            UIPasteboard.general.string = url.absoluteString
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(alert, animated: true)
    }
}

/// 存相册：需要 Info.plist 的 NSPhotoLibraryAddUsageDescription 才会弹授权。
/// 用户拒绝则回调 error，这里给提示，不再静默失败。
final class PhotoSaver: NSObject {
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
