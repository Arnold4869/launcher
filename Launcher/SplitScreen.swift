import SwiftUI
import WebKit

// MARK: - 分屏（上下两个独立 WebView + 可拖分隔条）

struct SplitViewScreen: View {
    let top: Bookmark
    let bottom: Bookmark
    /// 后台已打开页面的 PageState（有则复用其常驻 WebView，浏览状态保留）
    var topPage: PageState? = nil
    var bottomPage: PageState? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var topFraction: Double = 0.5
    @State private var expanded = false
    @State private var showTaskSwitcher = false
    @State private var bottomBarVisible = true
    @State private var barHideTask: DispatchWorkItem? = nil
    @EnvironmentObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore
    @AppStorage("splitFraction") private var savedFraction: Double = 0.5
    /// 3 秒无操作自动隐藏底部导航栏
    private func scheduleBarHide() {
        barHideTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { bottomBarVisible = false }
        }
        barHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if topFraction > 0.02 {
                    // 上半屏（拖到最底时关闭）
                    halfView(for: top, page: topPage)
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
                    halfView(for: bottom, page: bottomPage)
                        .overlay(alignment: .topLeading) { SplitLabel(bm: bottom) }
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .bottom) {
            // 底部浮动导航栏（悬浮在分屏之上，不改布局）
            if bottomBarVisible {
                PageBottomBar()
                    .environmentObject(wm)
                    .environmentObject(store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { scheduleBarHide() }
            }
        }
        .overlay {
            // 可拖动 + 吸边隐藏悬浮钮（与全屏页共用位置）
            FloatingMenuButton(expanded: expanded, onToggle: {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            })
            .onReceive(NotificationCenter.default.publisher(for: .fabActionHome)) { _ in
                expanded = false; savedFraction = topFraction
                wm.splitTop = nil
                wm.splitBottom = nil
                wm.splitTopPage = nil
                wm.splitBottomPage = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionTasks)) { _ in
                expanded = false; showTaskSwitcher = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionClearCache)) { _ in
                // 分屏页清缓存 = 上下两半都清
                expanded = false
                if let t = wm.splitTop { NotificationCenter.default.post(name: .launcherClearRefresh, object: t.id) }
                if let b = wm.splitBottom { NotificationCenter.default.post(name: .launcherClearRefresh, object: b.id) }
            }
        }
        .sheet(isPresented: $showTaskSwitcher) {
            TaskSwitcherView()
                .environmentObject(wm)
        }
        .onAppear {
            // 每次进入分屏都初始化为标准 55/45 分割（上次关一半残留的 0/1 不再带进来）
            topFraction = savedFraction <= 0.05 || savedFraction >= 0.95 ? 0.5 : savedFraction
        }
    }

    private enum Half { case top, bottom }

    /// 半屏内容：有 PageState 复用其常驻 WebView，否则新建
    @ViewBuilder
    private func halfView(for bm: Bookmark, page: PageState?) -> some View {
        SplitWebView(bm: bm, page: page, onWebViewTap: {
            if !bottomBarVisible {
                withAnimation(.easeInOut(duration: 0.2)) { bottomBarVisible = true }
            }
            scheduleBarHide()
        })
    }

    /// 关闭一半：保留的半屏转成全屏页（wm.open 复用已有 PageState 时浏览状态保留）
    private func closeHalf(_ half: Half) {
        savedFraction = 0.5
        let survivor = half == .bottom ? top : bottom
        // 清分屏状态（LauncherApp zIndex3 层消失）+ dismiss 关掉 SplitFlowView 的 fullScreenCover
        wm.splitTop = nil
        wm.splitBottom = nil
        wm.splitTopPage = nil
        wm.splitBottomPage = nil
        dismiss()
        // 保留的半屏转正为全屏页（如果它在 pages 里，直接全屏不重建；否则新开）
        wm.open(survivor)
    }
}

/// 分屏内 WebView：优先复用 PageState 缓存实例（浏览状态保留），无则新建
struct SplitWebView: UIViewRepresentable {
    let bm: Bookmark
    var page: PageState? = nil
    /// 单击网页空白处回调（底部导航栏唤出用；不吞触摸）
    var onWebViewTap: (() -> Void)? = nil

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var onWebViewTap: (() -> Void)? = nil
        var clearRefreshObserver: NSObjectProtocol? = nil
        @objc func webViewTapped() { onWebViewTap?() }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        deinit {
            if let obs = clearRefreshObserver { NotificationCenter.default.removeObserver(obs) }
        }

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
            page?.captureSnapshot()
        }
        weak var page: PageState? = nil
        let bm: Bookmark
        init(_ bm: Bookmark) { self.bm = bm }
    }

    func makeUIView(context: Context) -> WKWebView {
        let fresh: WKWebView
        if let page {
            // 复用常驻实例：重新接上 delegate（Basic Auth / 登录填充），不重载页面
            fresh = page.webView
            // 摘掉全屏路径挂的边缘手势（target 已随旧 Coordinator 释放，避免悬垂）
            for g in fresh.gestureRecognizers ?? [] where g is UIScreenEdgePanGestureRecognizer {
                fresh.removeGestureRecognizer(g)
            }
        } else {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.allowsBackForwardNavigationGestures = true
            wv.pageZoom = bm.scale
            if bm.desktopUA { wv.customUserAgent = PageWebView.desktopUserAgent }
            if let url = URL(string: bm.urlString) { wv.load(URLRequest(url: url)) }
            fresh = wv
        }
        fresh.navigationDelegate = context.coordinator
        fresh.currentBookmark = bm
        context.coordinator.page = page
        context.coordinator.onWebViewTap = onWebViewTap
        // 浏览器式：单击网页任意处唤出底部导航栏；不吞触摸
        if onWebViewTap != nil && !(fresh.gestureRecognizers ?? []).contains(where: { $0.name == "barRevealTap" }) {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.webViewTapped))
            tap.name = "barRevealTap"
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            fresh.addGestureRecognizer(tap)
        }
        // 清缓存刷新（分屏 FAB 触发时上下两半都要响应）
        context.coordinator.clearRefreshObserver = NotificationCenter.default.addObserver(
            forName: .launcherClearRefresh, object: nil, queue: .main) { [weak fresh] note in
            guard let targetID = note.object as? UUID, let fresh, fresh.currentBookmark.id == targetID else { return }
            guard let url = URL(string: bm.urlString), let host = url.host else { fresh.reload(); return }
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
                let matching = records.filter { $0.displayName.contains(host) }
                WKWebsiteDataStore.default().removeData(ofTypes: types, for: matching) {
                    DispatchQueue.main.async { fresh.reload() }
                }
            }
        }
        return fresh
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
    /// top 书签若已是打开页，复用其 WebView
    var topPage: PageState? = nil
    @ObservedObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    @State private var bottom: Bookmark?
    @State private var bottomPage: PageState?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let bottom {
            SplitViewScreen(top: top, bottom: bottom, topPage: topPage, bottomPage: bottomPage)
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
                                        bottomPage = page
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
    /// 发起分屏的页面（若它本身是已打开页，进分屏时复用其 WebView）
    var topPage: PageState? = nil
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        pickerContent
    }

    private var pickerContent: some View {
        NavigationStack {
            ScrollView {
                // 已打开的后台页面：直接选为下半屏（复用常驻 WebView，浏览状态保留）
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
                                    wm.splitTopPage = topPage
                                    wm.splitBottom = page.bookmark
                                    wm.splitBottomPage = page
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
                            wm.splitTopPage = topPage
                            wm.splitBottom = bm
                            wm.splitBottomPage = nil
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
    var topPage: PageState? = nil
    var bottom: Bookmark? = nil
}
