import SwiftUI
import WebKit

// MARK: - 页面容器：同一个页面在全屏/悬浮两形态间切换，WebView 常驻不重建

struct PageHost: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy

    var body: some View {
        let isFloating = page.id == wm.floatingID
        let isFullscreen = page.id == wm.fullscreenID

        Group {
            if isFloating {
                FloatingWindow(page: page, wm: wm, geo: geo)
            } else if isFullscreen {
                FullscreenPage(page: page, wm: wm)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
            }
            // 既不悬浮也不全屏 = 后台保留（隐藏），WebView 不销毁
        }
    }
}

// MARK: - 悬浮窗（预览 + 拖动 + 底部拉条调大小）

struct FloatingWindow: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy

    @State private var dragging = false

    var body: some View {
        let s = wm.floatingSize
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 4) {
                Text(page.bookmark.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    wm.closePage(page.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))

            // 页面预览
            PageWebView(page: page)
                .frame(width: s, height: s)

            // 底部拉条：上下拖调大小
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(height: 16)
                .contentShape(Rectangle())
                .overlay {
                    Rectangle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 36, height: 4)
                        .cornerRadius(2)
                }
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            // 往上拖 = 变大
                            wm.floatingSize = min(300, max(70, wm.floatingSize - v.translation.height / 3))
                        }
                )
        }
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .position(x: wm.floatingPos.x, y: wm.floatingPos.y)
        // 整窗拖动
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in
                    dragging = true
                    wm.floatingPos.x = max(60, min(geo.size.width - 60, wm.floatingPos.x + v.translation.width / 8))
                    wm.floatingPos.y = max(80, min(geo.size.height - 80, wm.floatingPos.y + v.translation.height / 8))
                }
                .onEnded { _ in dragging = false }
        )
        // 轻点标题栏 = 切换（页面区被 WebView 占用，标题栏是明确的点击目标）
        .onTapGesture { location in
            // 只有标题栏区域点击才算切换，页面区留给长按
            if location.y < 20 { wm.swap() }
        }
    }
}

// MARK: - 全屏页面（含悬浮按钮组）

struct FullscreenPage: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore

    @State private var showQuickSettings = false
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
                    collapse(); wm.minimizeToFloating()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "pip.enter").font(.system(size: 15, weight: .semibold))
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

// MARK: - 常驻 WebView（同一页面全屏/悬浮共用实例）

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
            webView.customUserAgent = WebView.desktopUserAgent
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
        // 常驻实例：只更新动态属性，不重新 load（保留浏览状态）
        context.coordinator.edgeSwipeHome = edgeSwipeHome
        webView.currentBookmark = page.bookmark
        webView.pageZoom = zoom

        let wantUA = desktopUA ? WebView.desktopUserAgent : nil
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
}

extension WKWebView {
    // 挂在 webView 上供 auth challenge 取书签配置
    var currentBookmark: Bookmark {
        get { objc_getAssociatedObject(self, &kBookmarkKey) as? Bookmark ?? Bookmark() }
        set { objc_setAssociatedObject(self, &kBookmarkKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
private var kBookmarkKey: UInt8 = 0

struct WebView {
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
}
