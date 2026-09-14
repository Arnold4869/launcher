import UIKit
import WebKit

// MARK: - 页面分享
//
// 分享物按当前页自适应：
//   • 当前页本身就是一张图（URL 后缀 / contentType / 整页一张图）→「分享图片」直接下载图本体分享
//   • 普通网页 →「整页 PNG 长图」= createPDF 拿整页内容 → CGPDFDocument 逐页光栅化拼长图
//                「整页 PDF」= createPDF 原始输出（保留文字可搜索、可打印）
//   • 任何情况都可「分享网址」
// 头文件名带书签名，微信/邮件里能看出是什么页面。

enum PageShare {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif", "tiff", "svg"]

    /// 整页长图预滚动的上限步数（防无限滚动页面滚不完）
    private static let maxPrewarmSteps = 20
    /// 最终位图尺寸上限（像素高 / 总像素面积）：长文章 PDF 页数多，不封顶会吃爆内存
    private static let maxPixelHeight: CGFloat = 20000
    private static let maxPixelArea: CGFloat = 12_000_000

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

    // MARK: 整页 PNG 长图（走 createPDF 光栅化）
    //
    // 为什么不用「逐屏滚动截图拼接」（2.5.2 的做法，实测拿不到整页）：
    //   ① takeSnapshot 只渲染可见视口，滚完立刻截常拿到上一帧（白图/错位）；
    //   ② pageZoom≠1 时 JS 给的 CSS px 与视图 pt 不是同一单位，画布/裁切必然对不上；
    //   ③ 吸顶元素要额外摊平，还会破坏 fixed 搭壳的页面。
    // 官方 createPDF 明确包含「当前屏幕看不到的内容」（WWDC20「Discover WKWebView
    // enhancements」原话：including content not currently visible on the screen），
    // 所以正确路径是：createPDF → CGPDFDocument 逐页光栅化 → 拼成一张长图 → PNG。
    // 生成前先整页预滚动一趟触发懒加载图片（公众号文章这类是滚动才加载的）。

    private struct PageMetrics: Decodable {
        let h: Double
        let w: Double
        let y: Double
        let vh: Double
        let vw: Double
    }

    static func shareFullPagePNG(_ wv: WKWebView) {
        showWaiting("正在生成整页截图…")
        prewarmLazyContent(wv) {
            wv.createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case .success(let data):
                    guard let img = rasterizePDFToLongImage(data) else {
                        // 光栅化拿不到 → 退化为一屏截图，至少能分享出去
                        hideWaiting()
                        shareVisibleSnapshot(wv)
                        return
                    }
                    saveAndShare(img, rawName: wv.currentBookmark.name, suffix: "整页", ext: "png")
                case .failure:
                    hideWaiting()
                    shareVisibleSnapshot(wv)
                }
            }
        }
    }

    /// 整页预滚动：把懒加载的图片/段落都触发一遍，再滚回原位置。
    /// 否则 createPDF 出来的长图中间会是空白（图还没加载）。
    private static func prewarmLazyContent(_ wv: WKWebView, done: @escaping () -> Void) {
        wv.evaluateJavaScript(metricsJS) { res, _ in
            guard let s = res as? String,
                  let data = s.data(using: .utf8),
                  let m = try? JSONDecoder().decode(PageMetrics.self, from: data),
                  m.h > m.vh, m.vh > 1 else {
                done()   // 不到一屏或量不到 → 不需要预滚动
                return
            }
            let step = CGFloat(m.vh) * 0.9
            let maxY = max(0, CGFloat(m.h) - CGFloat(m.vh))
            let originalY = CGFloat(m.y)
            var y: CGFloat = 0
            var steps = 0

            func next() {
                // 上限步数：够触发长文章的懒加载，又不至于让用户等太久
                guard y <= maxY, steps < maxPrewarmSteps else {
                    wv.evaluateJavaScript(scrollToJS(originalY), completionHandler: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { done() }
                    return
                }
                updateWaiting("正在加载整页内容…")
                let target = y
                wv.evaluateJavaScript(scrollToJS(target)) { _, _ in
                    steps += 1
                    y += step
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { next() }
                }
            }
            next()
        }
    }

    /// 把 createPDF 出来的（多页）PDF 逐页画进同一张画布，得到整页长图
    private static func rasterizePDFToLongImage(_ data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider), doc.numberOfPages > 0 else { return nil }

        // 页面尺寸：不同页宽度可能不同（WebKit 按视口宽分页），统一缩放到最宽页
        var boxes: [CGRect] = []
        var maxW: CGFloat = 0
        for i in 1...doc.numberOfPages {
            guard let page = doc.page(at: i) else { boxes.append(.zero); continue }
            let box = page.getBoxRect(.mediaBox)
            boxes.append(box)
            maxW = max(maxW, box.width)
        }
        guard maxW > 1 else { return nil }

        // 各页等比缩放到 maxW 后的高度 → 累计总高
        let heights: [CGFloat] = boxes.map { $0.width > 0 ? $0.height * maxW / $0.width : 0 }
        let totalH = heights.reduce(0, +)
        guard totalH > 1 else { return nil }

        // 像素规模封顶（长文章 PDF 页数很多，不封顶会直接把内存吃爆）
        var scale = min(UIScreen.main.scale, 2)
        if totalH * scale > maxPixelHeight { scale = maxPixelHeight / totalH }
        if maxW * totalH * scale * scale > maxPixelArea { scale = sqrt(maxPixelArea / (maxW * totalH)) }
        scale = max(scale, 0.25)

        let pxW = max(1, Int((maxW * scale).rounded()))
        let pxH = max(1, Int((totalH * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        // 白底：PNG 不带透明，长图在深色聊天背景上也读得清
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)))

        var drawnFromTop: CGFloat = 0
        for i in 1...doc.numberOfPages {
            guard let page = doc.page(at: i), boxes[i - 1].width > 1 else { continue }
            let box = boxes[i - 1]
            let h = heights[i - 1]
            // CGContext 原点在左下：第 i 页（在长图中自上而下排序）的底边
            let bottomInCanvas = totalH - drawnFromTop - h
            let s = (maxW / box.width) * scale
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bottomInCanvas * scale)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
            ctx.clip(to: box)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            drawnFromTop += h
        }
        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    /// 落盘 + 分享（PNG/PDF/图片共用）
    private static func saveAndShare(_ img: UIImage, rawName: String, suffix: String, ext: String) {
        guard let data = img.pngData() else {
            hideWaiting(); showToastLater("图片编码失败"); return
        }
        let name = sanitizedFileName(rawName.isEmpty ? "页面\(suffix)" : rawName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(suffix).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            hideWaiting(); showToastLater("保存失败"); return
        }
        hideWaiting()
        shareItemsLater([url])
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
        // 同样先预滚动触发懒加载，否则 PDF 中间是空白
        prewarmLazyContent(wv) {
            wv.createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case .success(let data):
                    let name = sanitizedFileName(wv.currentBookmark.name.isEmpty ? "页面" : wv.currentBookmark.name)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(name)-整页.pdf")
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
