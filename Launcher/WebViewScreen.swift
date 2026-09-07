import SwiftUI
import WebKit

struct WebViewScreen: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: BookmarkStore

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
                onEdgeSwipeBack: { dismiss() })
            .ignoresSafeArea()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                // 单个悬浮钮：点击展开 返回主页 / 快捷设置
                VStack(spacing: 12) {
                    if expanded {
                        Button {
                            collapse(); dismiss()
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
                .padding(.trailing, 20)
                .padding(.bottom, 34)
            }
            .sheet(isPresented: $showQuickSettings) {
                QuickSettingsView(bookmarkID: bookmark.id,
                                  zoom: $zoom, fontAdjust: $fontAdjust, desktopUA: $desktopUA)
                    .environmentObject(store)
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

struct WebView: UIViewRepresentable {
    let bookmark: Bookmark
    let zoom: Double
    let fontAdjust: Double
    let desktopUA: Bool
    var onEdgeSwipeBack: () -> Void = {}

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var parent: WebView
        var lastAppliedFontAdjust: Int = 0
        init(_ parent: WebView) { self.parent = parent }

        @objc func edgeSwiped() {
            parent.onEdgeSwipeBack()
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

        // 左边缘右滑 → 返回主页
        let edgeGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.edgeSwiped))
        edgeGesture.edges = .left
        edgeGesture.delegate = context.coordinator
        webView.addGestureRecognizer(edgeGesture)

        if let url = URL(string: bookmark.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 缩放实时生效
        webView.pageZoom = zoom

        // UA 变化时切换并重载
        let wantUA = desktopUA ? Self.desktopUserAgent : nil
        if webView.customUserAgent != wantUA {
            webView.customUserAgent = wantUA
            webView.reload()
        }

        // 文字大小变化时实时注入
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
