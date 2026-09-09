import SwiftUI
import WebKit

// MARK: - 分屏（上下两个独立 WebView + 可拖分隔条）

struct SplitViewScreen: View {
    let top: Bookmark
    let bottom: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var topFraction: Double = 0.5
    @State private var expanded = false
    @EnvironmentObject var wm: WindowManager
    @AppStorage("splitFraction") private var savedFraction: Double = 0.5
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if topFraction > 0.02 {
                    // 上半屏（拖到最底时关闭）
                    SplitWebView(bm: top)
                        .frame(height: geo.size.height * max(topFraction, 0))
                        .overlay(alignment: .topLeading) { SplitLabel(bm: top) }
                }

                if topFraction > 0.02 && topFraction < 0.98 {
                    // 分隔条拉杆：拖到最上/最下 = 关闭对应半屏
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 14)
                        .contentShape(Rectangle())
                        .overlay {
                            // 【玻璃 → 原生 glassEffect/.regular】分隔条拉杆=拖拽控件
                            Capsule()
                                .fill(Color.clear)
                                .frame(width: 60, height: 5)
                                .launcherGlass(.regular, in: .capsule, interactive: false)
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    topFraction = min(1.0, max(0.0, topFraction + (v.location.y - v.startLocation.y) / geo.size.height))
                                }
                                .onEnded { v in
                                    // 拖到最上 = 关下半屏（只剩上半屏）；拖到最下 = 关上半屏
                                    if topFraction >= 0.95 {
                                        closeHalf(.bottom)
                                    } else if topFraction <= 0.05 {
                                        closeHalf(.top)
                                    }
                                }
                        )
                }

                if topFraction < 0.98 {
                    // 下半屏（拖到最顶时关闭）
                    SplitWebView(bm: bottom)
                        .overlay(alignment: .topLeading) { SplitLabel(bm: bottom) }
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            // 可拖动 + 吸边隐藏悬浮钮（与全屏页共用位置）
            FloatingMenuButton(expanded: expanded, onToggle: {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            })
            .onReceive(NotificationCenter.default.publisher(for: .fabActionHome)) { _ in
                expanded = false; savedFraction = topFraction
                wm.splitTop = nil
                wm.splitBottom = nil
            }
        }
        .onAppear {
            // 每次进入分屏都初始化为标准 55/45 分割（上次关一半残留的 0/1 不再带进来）
            topFraction = savedFraction <= 0.05 || savedFraction >= 0.95 ? 0.5 : savedFraction
        }
    }

    private enum Half { case top, bottom }

    /// 关闭一半：保留的半屏转成全屏页（wm.open 复用已有 PageState 时浏览状态保留）
    private func closeHalf(_ half: Half) {
        savedFraction = 0.5
        let survivor = half == .bottom ? top : bottom
        // 清分屏状态（LauncherApp zIndex3 层消失）+ dismiss 关掉 SplitFlowView 的 fullScreenCover
        wm.splitTop = nil
        wm.splitBottom = nil
        dismiss()
        // 保留的半屏转正为全屏页（如果它在 pages 里，直接全屏不重建；否则新开）
        wm.open(survivor)
    }
}

/// 分屏内独立 WebView（一次性实例，带配置）
struct SplitWebView: UIViewRepresentable {
    let bm: Bookmark

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let method = challenge.protectionSpace.authenticationMethod
            if !bm.basicAuthUser.isEmpty,
               method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
                completionHandler(.useCredential, URLCredential(user: bm.basicAuthUser,
                                                                password: bm.basicAuthPass,
                                                                persistence: .forSession))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
            webView.injectLoginFill()
        }
        let bm: Bookmark
        init(_ bm: Bookmark) { self.bm = bm }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.pageZoom = bm.scale
        if bm.desktopUA { wv.customUserAgent = PageWebView.desktopUserAgent }
        wv.currentBookmark = bm
        if let url = URL(string: bm.urlString) { wv.load(URLRequest(url: url)) }
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(bm) }
}

struct SplitLabel: View {
    let bm: Bookmark
    var body: some View {
        // 【玻璃 → 原生 glassEffect/.tinted】分屏标签=导航层浮标（书签名），内容不受影响
        Text(bm.name)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .launcherGlass(.tinted(.blue), in: .capsule, interactive: false)
            .padding(8)
    }
}

/// 分屏流程：先选下半屏书签（后台已打开的页面排前面，浏览状态保留），选中后切分屏
struct SplitFlowView: View {
    let top: Bookmark
    @ObservedObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    @State private var bottom: Bookmark?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let bottom {
            SplitViewScreen(top: top, bottom: bottom)
        } else {
            NavigationStack {
                ScrollView {
                    let openPages = wm.pages.filter { $0.bookmark.id != top.id }
                    if !openPages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已打开的页面")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                                ForEach(openPages) { page in
                                    Button {
                                        bottom = page.bookmark
                                    } label: {
                                        BookmarkCard(bm: page.bookmark)
                                            .overlay(alignment: .topTrailing) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.blue)
                                                    .padding(6)
                                            }
                                    }
                                }
                            }
                            Divider().padding(.vertical, 8)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                        ForEach(store.bookmarks.filter { $0.id != top.id }) { bm in
                            Button {
                                bottom = bm
                            } label: {
                                BookmarkCard(bm: bm)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("选下半屏书签")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
    }
}

/// 分屏选择器（从全屏页悬浮钮进入）：选下半屏书签 → 关全屏 → 弹分屏
struct SplitPickerView: View {
    let top: Bookmark
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // 已打开的后台页面：直接选为下半屏（浏览状态保留）
                let openPages = wm.pages.filter { $0.bookmark.id != top.id }
                if !openPages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已打开的页面")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                            ForEach(openPages) { page in
                                Button {
                                    wm.goHome()
                                    wm.splitTop = top
                                    wm.splitBottom = page.bookmark
                                    dismiss()
                                } label: {
                                    BookmarkCard(bm: page.bookmark)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                                .padding(6)
                                        }
                                }
                            }
                        }
                        Divider().padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                    ForEach(store.bookmarks.filter { $0.id != top.id }) { bm in
                        Button {
                            wm.goHome()
                            wm.splitTop = top
                            wm.splitBottom = bm
                            dismiss()
                        } label: {
                            BookmarkCard(bm: bm)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("选下半屏书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct SplitPair: Identifiable {
    let id = UUID()
    let top: Bookmark
    let bottom: Bookmark
}
