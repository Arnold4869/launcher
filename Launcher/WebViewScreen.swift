import SwiftUI
import WebKit

// MARK: - 页面容器

struct PageHost: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy

    var body: some View {
        let isFloating = page.id == wm.floatingID
        let isFullscreen = page.id == wm.fullscreenID

        Group {
            if isFloating && wm.showFloating {
                FloatingWindow(page: page, wm: wm, geo: geo)
            } else if isFullscreen {
                FullscreenPage(page: page, wm: wm)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
            }
            // 后台保留，WebView 不销毁
        }
    }
}

// MARK: - 悬浮窗（真实缩略图 + 标题栏 + 边角调整）

struct FloatingWindow: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy

    var body: some View {
        let w = wm.floatingWidth
        let h = wm.floatingHeight
        let screen = UIScreen.main.bounds
        // 等比缩放：取 min(scaleX, scaleY)，整页显示且字体不变形
        let s = min(w / screen.width, h / screen.height)

        VStack(spacing: 0) {
            // 标题栏：拖=移动窗口；点书签名=切换；×=关闭
            HStack(spacing: 4) {
                Text(page.bookmark.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { wm.swap() }
                Spacer()
                Button {
                    wm.closePage(page.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))
            .frame(width: w)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { v in
                        let halfW = w / 2 + 8
                        let halfH = h / 2 + 20
                        wm.floatingPos.x = max(halfW, min(geo.size.width - halfW, wm.floatingPos.x + v.translation.width / 8))
                        wm.floatingPos.y = max(halfH, min(geo.size.height - halfH, wm.floatingPos.y + v.translation.height / 8))
                    }
            )

            // 页面区域：整页等比缩放（scaleX=scaleY，字体不变形）
            // 窗口比例≠屏幕比例时留边，内容完整显示
            ZStack {
                PageWebView(page: page)
                    .frame(width: screen.width, height: screen.height)
                    .scaleEffect(s, anchor: .center)
                    .frame(width: w, height: h, alignment: .center)
                    .clipped()
                    .background(Color.black)

                // 边/角把手（只在边缘窄条，不挡中间）
                ResizeHandles(wm: wm, geo: geo)
            }
            .frame(width: w, height: h)
            .onTapGesture(count: 2) { wm.swap() }   // 双击页面区 = 切换（单击留给网页）
        }
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .position(x: wm.floatingPos.x, y: wm.floatingPos.y)
    }
}

/// 边/角调整把手（锚点式：拖哪条边，对面边固定）
struct ResizeHandles: View {
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy
    @State private var startW: CGFloat = 0
    @State private var startH: CGFloat = 0
    @State private var startPos: CGPoint = .zero
    @State private var started = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let edge: CGFloat = 14
            let corner: CGFloat = 24

            ZStack {
                // 上边：向上拖=变大（anchor bottom）
                handle(width: w - corner * 2, height: edge, x: w / 2, y: edge / 2, edgeCase: .top)
                // 下边：向下拖=变大（anchor top）
                handle(width: w - corner * 2, height: edge, x: w / 2, y: h - edge / 2, edgeCase: .bottom)
                // 左边：向左拖=变大（anchor right）
                handle(width: edge, height: h - corner * 2, x: edge / 2, y: h / 2, edgeCase: .left)
                // 右边：向右拖=变大（anchor left）
                handle(width: edge, height: h - corner * 2, x: w - edge / 2, y: h / 2, edgeCase: .right)

                // 四角：斜拖同时调宽高
                ForEach([Corner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { c in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .frame(width: corner, height: corner)
                        .position(cornerPos(c, w: w, h: h))
                        .gesture(cornerGesture(c))
                }
            }
        }
    }

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    enum EdgeCase { case top, bottom, left, right }

    private func cornerPos(_ c: Corner, w: CGFloat, h: CGFloat) -> CGPoint {
        switch c {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: w, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: h)
        case .bottomRight: return CGPoint(x: w, y: h)
        }
    }

    private func handle(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, edgeCase: EdgeCase) -> some View {
        Rectangle().fill(Color.clear).contentShape(Rectangle())
            .frame(width: width, height: height)
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !started {
                            startW = wm.floatingWidth
                            startH = wm.floatingHeight
                            startPos = wm.floatingPos
                            started = true
                        }
                        switch edgeCase {
                        case .right:
                            // 左边固定：宽度变，中心右移一半
                            wm.floatingWidth = startW + v.translation.width
                            wm.floatingPos.x = startPos.x + v.translation.width / 2
                        case .left:
                            // 右边固定：向左拖=向左扩大，中心右移一半
                            wm.floatingWidth = startW - v.translation.width
                            wm.floatingPos.x = startPos.x + v.translation.width / 2
                        case .bottom:
                            wm.floatingHeight = startH + v.translation.height
                            wm.floatingPos.y = startPos.y + v.translation.height / 2
                        case .top:
                            // 下边固定：向上拖=向上扩大，中心下移一半
                            wm.floatingHeight = startH - v.translation.height
                            wm.floatingPos.y = startPos.y + v.translation.height / 2
                        }
                        clamp()
                    }
                    .onEnded { _ in started = false }
            )
    }

    private func cornerGesture(_ c: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !started {
                    startW = wm.floatingWidth
                    startH = wm.floatingHeight
                    startPos = wm.floatingPos
                    started = true
                }
                var dw: CGFloat = 0
                var dh: CGFloat = 0
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch c {
                case .bottomRight:
                    dw = v.translation.width; dh = v.translation.height
                    dx = v.translation.width / 2; dy = v.translation.height / 2
                case .bottomLeft:
                    dw = -v.translation.width; dh = v.translation.height
                    dx = v.translation.width / 2; dy = v.translation.height / 2
                case .topRight:
                    dw = v.translation.width; dh = -v.translation.height
                    dx = v.translation.width / 2; dy = v.translation.height / 2
                case .topLeft:
                    dw = -v.translation.width; dh = -v.translation.height
                    dx = v.translation.width / 2; dy = v.translation.height / 2
                }
                wm.floatingWidth = startW + dw
                wm.floatingHeight = startH + dh
                wm.floatingPos.x = startPos.x + dx
                wm.floatingPos.y = startPos.y + dy
                clamp()
            }
            .onEnded { _ in started = false }
    }

    private func clamp() {
        wm.floatingWidth = min(geo.size.width - 40, max(70, wm.floatingWidth))
        wm.floatingHeight = min(560, max(90, wm.floatingHeight))
    }
}

// MARK: - 全屏页面

struct FullscreenPage: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore

    @State private var showQuickSettings = false
    @State private var showSplitPicker = false
    @State private var expanded = false
    @State private var zoom: Double
    @State private var fontAdjust: Double
    @State private var desktopUA: Bool

    init(page: PageState, wm: WindowManager) {
        self.page = page
        _wm = ObservedObject(wrappedValue: wm)
        _zoom = State(initialValue: page.bookmark.scale)
        _fontAdjust = State(initialValue: page.bookmark.fontAdjust)
        _desktopUA = State(initialValue: page.bookmark.desktopUA)
    }

    var body: some View {
        ZStack {
            PageWebView(page: page, zoom: zoom, fontAdjust: fontAdjust, desktopUA: desktopUA,
                        edgeSwipeHome: { wm.goHome() })

            VStack { Spacer()
                HStack { Spacer()
                    buttons
                        .padding(.trailing, 20)
                        .padding(.bottom, 34)
                }
            }
        }
        .sheet(isPresented: $showQuickSettings) {
            QuickSettingsView(bookmarkID: page.bookmark.id,
                              zoom: $zoom, fontAdjust: $fontAdjust, desktopUA: $desktopUA)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSplitPicker) {
            SplitPickerView(top: page.bookmark)
                .environmentObject(store)
                .environmentObject(wm)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if expanded {
                Button {
                    collapse(); wm.goHome()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "house").font(.system(size: 16, weight: .semibold))
                        Text("主页").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .transition(.scale.combined(with: .opacity))

                Button {
                    collapse(); showSplitPicker = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "square.split.2x1").font(.system(size: 15, weight: .semibold))
                        Text("分屏").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .transition(.scale.combined(with: .opacity))

                Button {
                    collapse(); showQuickSettings = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold))
                        Text("设置").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "xmark" : "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
    }

    private func collapse() {
        withAnimation(.spring(duration: 0.25)) { expanded = false }
    }
}

/// 页面内快捷设置：调整直接写回书签永久生效
struct QuickSettingsView: View {
    let bookmarkID: UUID
    @Binding var zoom: Double
    @Binding var fontAdjust: Double
    @Binding var desktopUA: Bool
    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("页面属性 (实时生效，自动保存)") {
                    VStack(alignment: .leading) {
                        Text("页面缩放: \(String(format: "%.1fx", zoom))")
                        Slider(value: $zoom, in: 0.5...3.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("文字大小: \(fontAdjust >= 0 ? "+" : "")\(Int(fontAdjust))%")
                        Slider(value: $fontAdjust, in: -50...100, step: 5)
                    }
                    Toggle("桌面版页面 (UA)", isOn: $desktopUA)
                }
                Section {
                    Button("完成") { saveAndDismiss() }
                }
            }
            .navigationTitle("快捷设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { saveAndDismiss() }
                }
            }
            .onDisappear { save() }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let idx = store.bookmarks.firstIndex(where: { $0.id == bookmarkID }) {
            store.bookmarks[idx].scale = zoom
            store.bookmarks[idx].fontAdjust = fontAdjust
            store.bookmarks[idx].desktopUA = desktopUA
        }
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }
}

// MARK: - 常驻 WebView

struct PageWebView: UIViewRepresentable {
    let page: PageState
    var zoom: Double = 1.0
    var fontAdjust: Double = 0
    var desktopUA: Bool = false
    var edgeSwipeHome: (() -> Void)? = nil

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var edgeSwipeHome: (() -> Void)? = nil

        @objc func edgeSwiped() {
            edgeSwipeHome?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        // HTTP Basic Auth / Digest 自动应答
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let method = challenge.protectionSpace.authenticationMethod
            let bm = webView.currentBookmark
            if !bm.basicAuthUser.isEmpty,
               method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
                let cred = URLCredential(user: bm.basicAuthUser,
                                         password: bm.basicAuthPass,
                                         persistence: .forSession)
                completionHandler(.useCredential, cred)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = zoom
        webView.currentBookmark = page.bookmark
        context.coordinator.edgeSwipeHome = edgeSwipeHome
        if desktopUA {
            webView.customUserAgent = PageWebView.desktopUserAgent
        }

        if edgeSwipeHome != nil {
            let edgeGesture = UIScreenEdgePanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.edgeSwiped))
            edgeGesture.edges = .left
            edgeGesture.delegate = context.coordinator
            webView.addGestureRecognizer(edgeGesture)
        }

        if let url = URL(string: page.bookmark.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.edgeSwipeHome = edgeSwipeHome
        webView.currentBookmark = page.bookmark
        webView.pageZoom = zoom

        let wantUA = desktopUA ? PageWebView.desktopUserAgent : nil
        if webView.customUserAgent != wantUA {
            webView.customUserAgent = wantUA
            webView.reload()
        }

        if fontAdjust != 0 {
            let js = "document.documentElement.style.webkitTextSizeAdjust='\(100 + Int(fontAdjust))%';"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
}

extension WKWebView {
    var currentBookmark: Bookmark {
        get { objc_getAssociatedObject(self, &kBookmarkKey) as? Bookmark ?? Bookmark() }
        set { objc_setAssociatedObject(self, &kBookmarkKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
private var kBookmarkKey: UInt8 = 0
