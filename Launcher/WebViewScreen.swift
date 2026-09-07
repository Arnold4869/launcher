import SwiftUI
import WebKit

// MARK: - 悬浮窗（可拖动 + 双指捏合调大小）

struct FloatingWindowView: View {
    @ObservedObject var wm: WindowManager
    @AppStorage("floatingSize") private var savedSize: Double = 90
    @State private var pos: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 70, y: 110)
    @State private var dragging = false
    @State private var size: CGFloat = 90
    @State private var pinchBase: CGFloat = 90

    var body: some View {
        let s = size
        VStack(spacing: 2) {
            Text(wm.floating?.name ?? "?")
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: s + 10)
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
                .frame(width: s, height: s)
                .overlay {
                    if let bm = wm.floating {
                        WebView(bookmark: bm, zoom: 0.4, fontAdjust: 0, desktopUA: bm.desktopUA,
                                onEdgeSwipeBack: {}, onEdgeSwipeBackEnabled: false,
                                onTap: { wm.tapFloating() })
                            .id(bm.id)   // bookmark 变了强制重建 WebView
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .allowsHitTesting(false)   // WebView 不接触摸，全部手势由外层接管
                    }
                }
        }
        .padding(6)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .position(x: pos.x, y: pos.y)
        // 统一手势：位移 < 8pt = 点击切换；否则拖动；双指捏合调大小
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if abs(v.translation.width) > 4 || abs(v.translation.height) > 4 {
                        dragging = true
                    }
                    if dragging { pos = v.location }
                }
                .onEnded { v in
                    dragging = false
                    if abs(v.translation.width) < 8 && abs(v.translation.height) < 8 {
                        wm.tapFloating()
                    } else {
                        clampToEdges()
                    }
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    size = min(220, max(60, pinchBase * v))
                }
                .onEnded { _ in
                    pinchBase = size
                    savedSize = Double(size)
                    clampToEdges()
                }
        )
        .onAppear {
            size = CGFloat(savedSize)
            pinchBase = CGFloat(savedSize)
        }
        .onChange(of: wm.floating?.id) { _ in
            pos = CGPoint(x: UIScreen.main.bounds.width - 70, y: 110)
        }
    }

    private func clampToEdges() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let half = size / 2 + 10
        pos.x = min(max(pos.x, half), w - half)
        pos.y = min(max(pos.y, half + 30), h - half)
    }
}

// MARK: - 分屏视图

struct SplitViewScreen: View {
    let top: Bookmark
    let bottom: Bookmark
    @Environment(\.dismiss) private var dismiss

    @State private var topFraction: Double = 0.5
    @State private var expanded = false
    @AppStorage("splitFraction") private var savedFraction: Double = 0.5

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                WebView(bookmark: top, zoom: top.scale, fontAdjust: top.fontAdjust,
                        desktopUA: top.desktopUA, onEdgeSwipeBack: {}, onEdgeSwipeBackEnabled: false)
                    .frame(height: geo.size.height * topFraction)
                    .overlay(alignment: .topLeading) {
                        SplitLabel(bm: top)
                    }

                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .overlay {
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 60, height: 5)
                            .cornerRadius(3)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                topFraction = min(0.85, max(0.15, topFraction + v.location.y / geo.size.height - v.startLocation.y / geo.size.height))
                            }
                    )

                WebView(bookmark: bottom, zoom: bottom.scale, fontAdjust: bottom.fontAdjust,
                        desktopUA: bottom.desktopUA, onEdgeSwipeBack: {}, onEdgeSwipeBackEnabled: false)
                    .overlay(alignment: .topLeading) {
                        SplitLabel(bm: bottom)
                    }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                if expanded {
                    Button {
                        collapse(); savedFraction = topFraction; dismiss()
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
            .padding(.trailing, 20)
            .padding(.bottom, 34)
        }
        .onAppear { topFraction = savedFraction }
    }

    private func collapse() {
        withAnimation(.spring(duration: 0.25)) { expanded = false }
    }
}

/// 分屏角落的小标签
struct SplitLabel: View {
    let bm: Bookmark

    var body: some View {
        let colors = CardPalette.colors(for: bm.colorIndex)
        Text(bm.name)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors[1].opacity(0.85), in: Capsule())
            .padding(8)
    }
}

// MARK: - 全屏视图（悬浮窗可点切换）

struct WebFullScreenView: View {
    let bookmark: Bookmark
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager

    @State private var showQuickSettings = false
    @State private var expanded = false
    @State private var zoom: Double
    @State private var fontAdjust: Double
    @State private var desktopUA: Bool

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        _zoom = State(initialValue: bookmark.scale)
        _fontAdjust = State(initialValue: bookmark.fontAdjust)
        _desktopUA = State(initialValue: bookmark.desktopUA)
    }

    var body: some View {
        WebView(bookmark: bookmark, zoom: zoom, fontAdjust: fontAdjust, desktopUA: desktopUA,
                onEdgeSwipeBack: { wm.minimizeCurrentToFloating() })
            .id(bookmark.id)   // 切换书签时强制重建 WebView
            .ignoresSafeArea()
            .overlay(alignment: .bottomTrailing) {
                floatingButtons
                    .padding(.trailing, 20)
                    .padding(.bottom, 34)
            }
            .sheet(isPresented: $showQuickSettings) {
                QuickSettingsView(bookmarkID: bookmark.id,
                                  zoom: $zoom, fontAdjust: $fontAdjust, desktopUA: $desktopUA)
                    .environmentObject(store)
            }
    }

    private var floatingButtons: some View {
        VStack(spacing: 12) {
            if expanded {
                Button {
                    collapse(); wm.goHome()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "house")
                            .font(.system(size: 16, weight: .semibold))
                        Text("主页").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .transition(.scale.combined(with: .opacity))

                Button {
                    collapse(); wm.minimizeCurrentToFloating()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 15, weight: .semibold))
                        Text("悬浮").font(.system(size: 9))
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
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
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

// MARK: - WKWebView 封装

struct WebView: UIViewRepresentable {
    let bookmark: Bookmark
    let zoom: Double
    let fontAdjust: Double
    let desktopUA: Bool
    var onEdgeSwipeBack: () -> Void = {}
    var onEdgeSwipeBackEnabled: Bool = true
    var onTap: (() -> Void)? = nil   // 整块点击（悬浮窗用，原生层捕获）

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var parent: WebView
        var lastAppliedFontAdjust: Int = 0
        init(_ parent: WebView) { self.parent = parent }

        @objc func edgeSwiped() {
            parent.onEdgeSwipeBack()
        }

        @objc func tapped() {
            parent.onTap?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontAdjust(webView)
        }

        private func applyFontAdjust(_ webView: WKWebView) {
            let adjust = parent.fontAdjust
            if adjust != 0 {
                let js = "document.documentElement.style.webkitTextSizeAdjust='\(100 + adjust)%';"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        // HTTP Basic Auth / Digest 自动应答
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let method = challenge.protectionSpace.authenticationMethod
            let bm = parent.bookmark
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

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.minimumZoomScale = 0.3
        webView.scrollView.maximumZoomScale = 5.0
        webView.pageZoom = zoom
        if desktopUA {
            webView.customUserAgent = Self.desktopUserAgent
        }

        if onEdgeSwipeBackEnabled {
            let edgeGesture = UIScreenEdgePanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.edgeSwiped))
            edgeGesture.edges = .left
            edgeGesture.delegate = context.coordinator
            webView.addGestureRecognizer(edgeGesture)
        }

        // 整块点击回调（悬浮窗切换用）
        if onTap != nil {
            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.tapped))
            tap.delegate = context.coordinator
            tap.cancelsTouchesInView = false
            webView.addGestureRecognizer(tap)
        }

        if let url = URL(string: bookmark.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoom

        let wantUA = desktopUA ? Self.desktopUserAgent : nil
        if webView.customUserAgent != wantUA {
            webView.customUserAgent = wantUA
            webView.reload()
        }

        let adjust = Int(fontAdjust)
        if adjust != context.coordinator.lastAppliedFontAdjust {
            context.coordinator.lastAppliedFontAdjust = adjust
            if adjust != 0 {
                let js = "document.documentElement.style.webkitTextSizeAdjust='\(100 + adjust)%';"
                webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                webView.reload()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(self)
        c.lastAppliedFontAdjust = Int(fontAdjust)
        return c
    }
}
