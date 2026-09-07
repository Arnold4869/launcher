import SwiftUI
import WebKit

struct WebViewScreen: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: BookmarkStore

    @State private var showQuickSettings = false
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
        WebView(bookmark: bookmark, zoom: zoom, fontAdjust: fontAdjust, desktopUA: desktopUA)
            .ignoresSafeArea()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                // 悬浮按钮组：返回主页 + 快捷设置
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    Button {
                        showQuickSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
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
}

/// 页面内快捷设置：滑杆实时生效，「保存到书签」写回持久化
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
                Section("页面属性 (实时生效)") {
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
                    Button("完成") { save() }
                }
            }
            .navigationTitle("快捷设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { save(); dismiss() }
                }
            }
            .onDisappear { save() }
        }
        .presentationDetents([.medium])
    }

    /// 调整直接写回书签永久生效
    private func save() {
        if let idx = store.bookmarks.firstIndex(where: { $0.id == bookmarkID }) {
            store.bookmarks[idx].scale = zoom
            store.bookmarks[idx].fontAdjust = fontAdjust
            store.bookmarks[idx].desktopUA = desktopUA
        }
    }
}

struct WebView: UIViewRepresentable {
    let bookmark: Bookmark
    let zoom: Double
    let fontAdjust: Double
    let desktopUA: Bool

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var lastAppliedFontAdjust: Int = 0
        init(_ parent: WebView) { self.parent = parent }

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

        // HTTP Basic Auth / NTLM 自动应答
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
