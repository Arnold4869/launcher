import SwiftUI
import WebKit

struct WebViewScreen: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WebView(bookmark: bookmark)
            .ignoresSafeArea()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 34)
            }
    }
}

struct WebView: UIViewRepresentable {
    let bookmark: Bookmark

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 文字大小偏移：每次页面加载后注入
            let adjust = Int(parent.bookmark.fontAdjust)
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
        // 持久化数据存储：cookie / localStorage 长期保存到磁盘
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.minimumZoomScale = 0.3
        webView.scrollView.maximumZoomScale = 5.0

        // 页面缩放（iOS 14+）
        webView.pageZoom = bookmark.scale

        if bookmark.desktopUA {
            webView.customUserAgent = Self.desktopUserAgent
        }

        if let url = URL(string: bookmark.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
