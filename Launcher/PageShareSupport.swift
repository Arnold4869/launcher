import UIKit
import WebKit

// MARK: - 页面分享
//
// 分享物按当前页自适应：
//   • 当前页本身就是一张图（URL 后缀 / contentType / 整页一张图）→「分享图片」直接下载图本体分享
//   • 普通网页 →「整页 PNG 长图」= 逐屏滚动截图拼接成一张长图（takeSnapshot 只给可见区域，
//                整页必须自己拼）；「整页 PDF」= WKWebView.createPDF（官方 API，一次出全篇）
//   • 任何情况都可「分享网址」
// 头文件名带书签名，微信/邮件里能看出是什么页面。

enum PageShare {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    /// 整页长图：分段上限（防极端长页面把内存吃爆 + 无限滚动页面截不完）
    private static let maxSegments = 40
    /// 每段之间的等待：等滚动 + WebKit 提交新帧
    private static let segmentDelay: Double = 0.35
    /// 最终位图尺寸上限（像素高 / 总像素面积）
    private static let maxPixelHeight: CGFloat = 12000
    private static let maxPixelArea: CGFloat = 16_000_000

    /// 当前页是否为纯图片页（决定「分享页面」菜单项显示成「分享图片」）
    static func isImagePage(_ wv: WKWebView, done: @escaping (Bool) -> Void) {
        guard let url = wv.url else { done(false); return }
        if imageExts.contains(url.pathExtension.lowercased()) { done(true); return }
        wv.evaluateJavaScript(imageProbeJS) { res, _ in
            done((res as? String)?.isEmpty == false)
        }
    }

    /// 菜单项调用：图片页 → 分享图片本体；普通页 → 整页 PNG 长图
    static func shareDefault(_ wv: WKWebView) {
        isImagePage(wv) { isImg in
            if isImg {
                shareCurrentImage(wv)
            } else {
                shareFullPagePNG(wv)
            }
        }
    }

    // MARK: 整页 PNG 长图（逐屏滚动截图 + 拼接）
    //
    // takeSnapshot 只给「当前可见视口」，整页必须自己拼：先量 document 高度 → 按视口高逐屏滚动、
    // 每屏截一张 → 按「本屏应覆盖的页面区间」裁切后贴到同一画布。
    // 两个必须处理的坑：
    //   ① 最后一段滚动会被 clamp 到最底部（scrollY = 页面高 - 视口高），若整屏直接贴会与上一屏
    //      重影 → 只取「本屏尚未覆盖的那一段」的源图区域（cropping）。
    //   ② position:fixed/sticky 元素（吸顶导航）会在每一屏重复出现 → 截图期间临时改 static，
    //      截完恢复。截完还要把用户原来的滚动位置还原。
    // 位图尺寸有上限（maxPixelHeight / maxPixelArea），长页面自动降采样，避免内存爆掉。

    private struct PageMetrics: Decodable {
        let h: Double
        let w: Double
        let y: Double
        let vh: Double
        let vw: Double
    }

    static func shareFullPagePNG(_ wv: WKWebView) {
        showWaiting("正在生成整页截图…")
        wv.evaluateJavaScript(metricsJS) { res, _ in
            guard let s = res as? String,
                  let data = s.data(using: .utf8),
                  let m = try? JSONDecoder().decode(PageMetrics.self, from: data),
                  m.h > 1, m.vh > 1 else {
                // 量不到尺寸（受限页面/JS 被禁）→ 退化成可见区域截图，至少能分享出去
                shareVisibleSnapshot(wv)
                return
            }
            captureFullPage(wv, metrics: m)
        }
    }

    private static func captureFullPage(_ wv: WKWebView, metrics m: PageMetrics) {
        let viewportH = CGFloat(m.vh)
        let pageH = CGFloat(m.h)
        let totalH = min(pageH, viewportH * CGFloat(maxSegments))

        // 画布缩放：像素高 + 总像素面积双封顶
        var scale = min(UIScreen.main.scale, 2)
        if totalH * scale > maxPixelHeight { scale = maxPixelHeight / totalH }
        let widthPt = wv.bounds.width > 1 ? wv.bounds.width : CGFloat(m.vw)
        if widthPt * totalH * scale * scale > maxPixelArea {
            scale = sqrt(maxPixelArea / (widthPt * totalH))
        }
        scale = max(scale, 0.3)

        let pxW = max(1, Int((widthPt * scale).rounded()))
        let pxH = max(1, Int((totalH * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else {
            hideWaiting(); showToastLater("整页截图失败：画布创建不了"); return
        }
        // 白底：PNG 不带透明，长图在深色聊天背景上也可读
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)))

        let originalY = CGFloat(m.y)
        let segCount = max(1, Int(ceil(totalH / viewportH)))
        // 先把吸顶/固定元素临时摊平，避免每屏重复
        wv.evaluateJavaScript(neutralizeFixedJS, completionHandler: nil)

        var index = 0

        func finishUp() {
            wv.evaluateJavaScript(restoreFixedJS, completionHandler: nil)
            wv.evaluateJavaScript(scrollToJS(originalY), completionHandler: nil)
            guard let cg = ctx.makeImage() else {
                hideWaiting(); showToastLater("整页截图失败"); return
            }
            let img = UIImage(cgImage: cg, scale: scale, orientation: .up)
            guard let png = img.pngData() else {
                hideWaiting(); showToastLater("PNG 编码失败"); return
            }
            let name = sanitizedFileName(wv.currentBookmark.name.isEmpty ? "页面长图" : wv.currentBookmark.name)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)-整页.png")
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                hideWaiting(); showToastLater("长图保存失败"); return
            }
            hideWaiting()
            shareItemsLater([url])
        }

        func captureNext() {
            guard index < segCount else { finishUp(); return }
            let i = index
            let top = CGFloat(i) * viewportH                 // 本屏应覆盖的页面区间 [top, bottom)
            let bottom = min(totalH, top + viewportH)
            let scrollY = min(top, max(0, pageH - viewportH))   // 滚到底会被 clamp
            wv.evaluateJavaScript(scrollToJS(scrollY)) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + segmentDelay) {
                    updateWaiting("正在生成整页截图… \(i + 1)/\(segCount)")
                    wv.takeSnapshot(with: nil) { image, _ in
                        if let full = image?.cgImage, bottom > top {
                            // 只取本屏「尚未覆盖」的那段源图，规避末屏 clamp 重影
                            let srcTopPx = CGFloat(full.height) * ((top - scrollY) / viewportH)
                            let srcHPx = CGFloat(full.height) * ((bottom - top) / viewportH)
                            let src = CGRect(x: 0, y: srcTopPx.rounded(),
                                             width: CGFloat(full.width),
                                             height: max(1, srcHPx.rounded()))
                            if let piece = full.cropping(to: src) {
                                // CGContext 原点在左下：底对齐换算
                                let yPx = (totalH - bottom) * scale
                                ctx.draw(piece, in: CGRect(x: 0, y: yPx,
                                                           width: CGFloat(pxW),
                                                           height: (bottom - top) * scale))
                            }
                        }
                        index += 1
                        captureNext()
                    }
                }
            }
        }
        captureNext()
    }

    /// 量页面尺寸（CSS px；scrollY / innerHeight 同单位）
    private static let metricsJS = """
    (function(){
      try {
        var d = document.documentElement, b = document.body;
        var h = Math.max(d.scrollHeight, d.offsetHeight,
                         b ? b.scrollHeight : 0, b ? b.offsetHeight : 0);
        var w = Math.max(d.scrollWidth, d.clientWidth, b ? b.scrollWidth : 0);
        var y = window.scrollY || window.pageYOffset || 0;
        return JSON.stringify({h: Math.round(h), w: Math.round(w), y: Math.round(y),
                               vh: Math.round(window.innerHeight), vw: Math.round(window.innerWidth)});
      } catch (e) { return ''; }
    })();
    """

    /// 截图期间把 fixed/sticky 摊平成 static（吸顶导航只出现一次，不在每屏重复）。
    /// 保守处理：跳过高度接近视口的元素 —— 那多半是「整页用 fixed 搭壳」的 app 式页面，
    /// 摊平会直接改坏布局。
    private static let neutralizeFixedJS = """
    (function(){
      try {
        if (window.__launcherFixedSaved) return '0';
        var vh = window.innerHeight || 0;
        var saved = [], all = document.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var cs = window.getComputedStyle(el);
          if (cs && (cs.position === 'fixed' || cs.position === 'sticky')) {
            var r = el.getBoundingClientRect();
            if (vh > 0 && r.height >= vh * 0.9) continue;   // 疑似布局壳，不动
            saved.push({el: el, pos: el.style.position});
            try { el.style.setProperty('position', 'static', 'important'); } catch (e2) {}
          }
        }
        window.__launcherFixedSaved = saved;
        return String(saved.length);
      } catch (e) { return ''; }
    })();
    """

    private static let restoreFixedJS = """
    (function(){
      try {
        var saved = window.__launcherFixedSaved;
        if (!saved) return '';
        for (var i = 0; i < saved.length; i++) {
          try {
            if (saved[i].pos) {
              saved[i].el.style.setProperty('position', saved[i].pos, 'important');
            } else {
              saved[i].el.style.removeProperty('position');
            }
          } catch (e2) {}
        }
        window.__launcherFixedSaved = null;
        return 'ok';
      } catch (e) { return ''; }
    })();
    """

    private static func scrollToJS(_ y: CGFloat) -> String {
        "try{window.scrollTo(0,\(Int(y.rounded())));}catch(e){}"
    }

    // MARK: PNG 截图（可见区域，全分辨率）—— 仅作整页失败时的兜底
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

    private static func updateWaiting(_ msg: String) {
        hudLabel?.text = msg
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
