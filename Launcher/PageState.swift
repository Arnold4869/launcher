import Foundation
import WebKit
import UIKit
import Combine

/// 一个打开的页面（常驻 WebView，最多 4 个）
/// webView 实例缓存在这里：SwiftUI 视图树卸载只把它从父视图摘下，实例由本类强持有不销毁，
/// 后台/全屏/分屏之间切换 = 同一 WKWebView 在不同容器间搬移，浏览状态全程保留。
final class PageState: ObservableObject, Identifiable {
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
        // 视频/音频站点（抖音、B站等）：内联播放 + 允许自动播放
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        // 图片长按分享菜单（JS 检测 + 原生菜单；公开 contextMenu 委托对纯图片不触发）
        WebViewLongPressImage.install(into: config)
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

    /// 快照降采样到缩略图尺寸：多任务卡片最多几百 pt 宽，存完整屏图（一张几 MB）纯浪费内存，
    /// 旧手机 4 张快照就是十几 MB，内存一紧张就被系统回收进程 → 突然刷新。缩略图一张几十 KB。
    static func downscale(_ image: UIImage, maxWidth: CGFloat = 420) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        guard w > maxWidth else { return image }
        let ratio = maxWidth / w
        let newSize = CGSize(width: maxWidth, height: h * ratio)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1          // 缩略图不需要 retina，直接 1x
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// 空白快照检测：采样像素，全白或全透明（页面没渲染完）返回 true
    static func isBlankSnapshot(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let w = max(1, cg.width / 8), h = max(1, cg.height / 8)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return true }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var total = 0.0, count = 0.0
        for i in 0..<(w * h) {
            let r = Double(buf[i * 4]), g = Double(buf[i * 4 + 1]), b = Double(buf[i * 4 + 2])
            // 亮度接近 1（纯白）或 alpha 接近 0（透明）都算"空"
            let a = Double(buf[i * 4 + 3])
            if a < 8 { continue }
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            total += lum
            count += 1
        }
        guard count > 0 else { return true }
        return (total / count) > 0.985
    }

    /// 是否为当前前台全屏页。前台页不截图（阅读时避免每次翻页触发快照卡顿），
    /// 只在切到后台/打开多任务时才截。由 WindowManager 维护。
    var isForeground = false

    /// 是否已释放（下次访问 WebView 时重建并重载）
    private(set) var released = false
    private var heldWebView: WKWebView?

    /// 抓当前画面到缩略图（多任务卡片用）
    /// takeSnapshot 是只读操作，不重载、不重渲染，不会引起"翻页闪烁"——
    /// 之前的闪烁根因是 pageZoom 写入（已用 lastZoom 门控修复），不是截图。
    /// 所以全屏浏览期间也要抓，多任务打开时预览图才是现成的。
    ///
    /// 防抖：didFinish 连环触发（小说翻页/SPA 局部刷新）会合并成一次截图，
    /// 避免旧手机每次翻页都跑一遍「临时挂载 + 异步截图 + 像素循环 + 降采样」。
    private var snapshotDebounce: DispatchWorkItem?
    func captureSnapshot() {
        // 前台页跳过：阅读/翻页时 didFinish 连环触发截图会卡（旧手机尤其明显）。
        // 前台页的预览图由「切到后台 / 打开多任务」时统一补抓（见 refreshAllSnapshots）。
        guard !isForeground else { return }
        snapshotDebounce?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.performSnapshot() }
        snapshotDebounce = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    private func performSnapshot() {
        let wv = webView
        let needsTempMount = wv.window == nil || wv.frame.width <= 1
        let bounds = UIScreen.main.bounds
        if needsTempMount {
            // 后台页不在视图树：临时挂到屏幕外（负坐标，不可见）再截，截完摘掉
            wv.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: bounds.height)
            if let window = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                window.addSubview(wv)
            }
        }
        // afterScreenUpdates 默认 false：抓"当前已提交的帧"，不强制下一轮渲染。
        // 被 sheet 盖住 / 挂在屏幕外的页面，强制渲染反而抓不到（WebKit 会暂停离屏渲染），
        // 抓已提交帧才是可靠的。takeSnapshot 异步，回调里才摘离屏挂载。
        wv.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, let image else {
                if needsTempMount { DispatchQueue.main.async { wv.removeFromSuperview() } }
                return
            }
            // 主线程先摘离屏挂载 + 取标题（title 读取要在主线程），像素运算移后台
            if needsTempMount { wv.removeFromSuperview() }
            let title = wv.title ?? self.bookmark.name
            // 空白检测（几万次像素循环）+ 降采样：全放后台线程，旧手机不卡主线程
            DispatchQueue.global(qos: .userInitiated).async {
                guard !Self.isBlankSnapshot(image) else { return }
                let thumb = Self.downscale(image)
                DispatchQueue.main.async { [weak self] in
                    self?.snapshot = thumb
                    self?.pageTitle = title
                }
            }
        }
    }
}
