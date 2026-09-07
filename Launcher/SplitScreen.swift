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
                SplitWebView(bm: top)
                    .frame(height: geo.size.height * topFraction)
                    .overlay(alignment: .topLeading) { SplitLabel(bm: top) }

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
                                topFraction = min(0.85, max(0.15, topFraction + (v.location.y - v.startLocation.y) / geo.size.height))
                            }
                    )

                SplitWebView(bm: bottom)
                    .overlay(alignment: .topLeading) { SplitLabel(bm: bottom) }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                if expanded {
                    Button {
                        collapse(); savedFraction = topFraction
                        wm.splitTop = nil
                        wm.splitBottom = nil
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
        if let url = URL(string: bm.urlString) { wv.load(URLRequest(url: url)) }
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(bm) }
}

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

/// 分屏流程：先选下半屏书签，选中后切分屏
struct SplitFlowView: View {
    let top: Bookmark
    @ObservedObject var store: BookmarkStore
    @State private var bottom: Bookmark?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let bottom {
            SplitViewScreen(top: top, bottom: bottom)
        } else {
            NavigationStack {
                ScrollView {
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
