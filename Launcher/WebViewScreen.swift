import SwiftUI
import WebKit

// MARK: - 页面容器

struct PageHost: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    let geo: GeometryProxy

    var body: some View {
        let isFullscreen = page.id == wm.fullscreenID

        Group {
            if isFullscreen {
                FullscreenPage(page: page, wm: wm)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
            }
            // 后台页不挂载视图，但 WKWebView 实例缓存在 PageState 里不销毁，
            // 重新打开 = 同一实例重新挂载，浏览状态/登录态全程保留。
        }
    }
}

// MARK: - 全屏页面

struct FullscreenPage: View {
    let page: PageState
    @ObservedObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore
    @State private var showQuickSettings = false
    @State private var showSplitPicker = false
    @State private var showTaskSwitcher = false
    @State private var expanded = false
    @State private var zoom: Double
    @State private var fontAdjust: Double
    @State private var uaMode: Int
    @State private var showFind = false
    @State private var showToolsPanel = false

    init(page: PageState, wm: WindowManager) {
        self.page = page
        _wm = ObservedObject(wrappedValue: wm)
        _zoom = State(initialValue: page.bookmark.scale)
        _fontAdjust = State(initialValue: page.bookmark.fontAdjust)
        _uaMode = State(initialValue: page.bookmark.uaMode)
    }

    var body: some View {
        ZStack {
            PageWebView(page: page, zoom: zoom, fontAdjust: fontAdjust, uaMode: uaMode,
                        onBarReveal: {
                            // 三指向下滑 → 唤出底部导航栏
                            NotificationCenter.default.post(name: .launcherPageTapped, object: nil)
                        })
        }
        .overlay {
            // 可拖动 + 自动吸边隐藏的悬浮钮（位置持久化，跟主屏共用）
            FloatingMenuButton(expanded: expanded, onToggle: {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            })
            .onReceive(NotificationCenter.default.publisher(for: .fabActionHome)) { _ in
                expanded = false; wm.goHome()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionTasks)) { _ in
                expanded = false; showTaskSwitcher = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionSplit)) { _ in
                expanded = false; showSplitPicker = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionClearCache)) { _ in
                expanded = false
                NotificationCenter.default.post(name: .launcherClearRefresh, object: page.bookmark.id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fabActionSettings)) { _ in
                expanded = false; showQuickSettings = true
            }
        }
        .overlay(alignment: .bottom) {
            // 底部浮动导航栏：悬浮在网页之上（不改布局、不触发重渲染）
            // 单击网页任意处唤出；显示 3 秒后自动隐藏
            PageBottomBarLayer(mode: .page, currentPage: page, onMore: {
                showToolsPanel = true
            }, onFind: {
                showFind = true
            })
            .environmentObject(wm)
            .environmentObject(store)
        }
        .overlay(alignment: .bottom) {
            // 查找条：压在底栏之上，从下边安全区升起
            if showFind, let wv = page.webViewHolder {
                PageFindBar(wv: wv, isPresented: $showFind)
                    .padding(.bottom, 76)   // 浮在底栏之上，不跟底栏叠一起
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showToolsPanel) {
            if let wv = page.webViewHolder {
                PageToolsPanel(wv: wv,
                               onFind: { showFind = true },
                               onZoom: { showQuickSettings = true })
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showQuickSettings) {
            QuickSettingsView(bookmarkID: page.bookmark.id,
                              zoom: $zoom, fontAdjust: $fontAdjust, uaMode: $uaMode)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSplitPicker) {
            SplitPickerView(top: page.bookmark, topPage: page)
                .environmentObject(store)
                .environmentObject(wm)
        }
        .sheet(isPresented: $showTaskSwitcher) {
            TaskSwitcherView()
                .environmentObject(store)
                .environmentObject(wm)
        }
        // 工具面板/快捷设置里改了访问标识 → 同步到本页 @State（否则 QuickSettings 的绑定是旧值）
        .onReceive(store.$bookmarks) { list in
            if let m = list.first(where: { $0.id == page.bookmark.id }) {
                // PageState.bookmark 也同步：它是值拷贝，不同步则退出页面再进来 UA/名称回退旧值
                if page.bookmark != m { page.bookmark = m }
                if m.uaMode != uaMode { uaMode = m.uaMode }
            }
        }
    }
}

/// 页面内快捷设置：调整直接写回书签永久生效
struct QuickSettingsView: View {
    let bookmarkID: UUID
    @Binding var zoom: Double
    @Binding var fontAdjust: Double
    @Binding var uaMode: Int
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
                    Picker("访问标识", selection: $uaMode) {
                        ForEach(0..<UserAgentOption.titles.count, id: \.self) { m in
                            Text(UserAgentOption.titles[m]).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("快捷设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { saveAndDismiss() }
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
            store.bookmarks[idx].uaMode = uaMode
            store.bookmarks[idx].desktopUA = (uaMode == 2)   // legacy 同步
        }
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }
}

/// 分屏页快捷设置：直接读写书签字段（store 是 @Published，改动即时反映到 SplitWebView 并永久保存）
struct SplitQuickSettingsView: View {
    let bookmarkID: UUID
    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss

    private var index: Int? { store.bookmarks.firstIndex(where: { $0.id == bookmarkID }) }

    var body: some View {
        NavigationStack {
            Form {
                if let i = index {
                    Section("页面属性 (实时生效，自动保存)") {
                        VStack(alignment: .leading) {
                            Text("页面缩放: \(String(format: "%.1fx", store.bookmarks[i].scale))")
                            Slider(value: $store.bookmarks[i].scale, in: 0.5...3.0, step: 0.1)
                        }
                        VStack(alignment: .leading) {
                            let fa = store.bookmarks[i].fontAdjust
                            Text("文字大小: \(fa >= 0 ? "+" : "")\(Int(fa))%")
                            Slider(value: $store.bookmarks[i].fontAdjust, in: -50...100, step: 5)
                        }
                        Picker("访问标识", selection: $store.bookmarks[i].uaMode) {
                            ForEach(0..<UserAgentOption.titles.count, id: \.self) { m in
                                Text(UserAgentOption.titles[m]).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("快捷设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 常驻 WebView

struct PageWebView: UIViewRepresentable {
    let page: PageState
    var zoom: Double = 1.0
    var fontAdjust: Double = 0
    var uaMode: Int = 0
    /// 三指向下滑唤出底部导航栏（2.6.1 起取代「单击任意处唤出」，避免误触发遮挡内容）
    var onBarReveal: (() -> Void)? = nil
    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        weak var page: PageState? = nil
        var onBarReveal: (() -> Void)? = nil
        var lastZoom: Double? = nil
        var lastFontAdjust: Double? = nil
        var clearRefreshObserver: NSObjectProtocol? = nil

        deinit {
            if let obs = clearRefreshObserver { NotificationCenter.default.removeObserver(obs) }
        }

        @objc func barRevealed() { onBarReveal?() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
            webView.injectLoginFill()
            page?.captureSnapshot()
        }

        /// Web 内容进程被系统回收（内存压力）→ 立刻重载，避免白屏；这是"看着像突然刷新"的常见来源
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
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
        // 复用 PageState 缓存的 WKWebView 实例（后台/全屏/分屏间搬移不销毁）
        let webView = page.webView
        webView.navigationDelegate = context.coordinator
        webView.pageZoom = zoom
        webView.currentBookmark = page.bookmark
        context.coordinator.onBarReveal = onBarReveal

        // 清缓存刷新：删掉该书签域名的全部站点数据（缓存/cookie/localStorage，登录态会丢）后重载
        context.coordinator.clearRefreshObserver = NotificationCenter.default.addObserver(
            forName: .launcherClearRefresh, object: nil, queue: .main) { [weak webView] note in
            guard let targetID = note.object as? UUID,
                  let webView, webView.currentBookmark.id == targetID else { return }
            guard let url = URL(string: webView.currentBookmark.urlString),
                  let host = url.host else { webView.reload(); return }
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
                let matching = records.filter { $0.displayName.contains(host) }
                WKWebsiteDataStore.default().removeData(ofTypes: types, for: matching) {
                    DispatchQueue.main.async { webView.reload() }
                }
            }
        }

        // 访问标识：首次创建直接设值不 reload（下面马上要 load 初始 URL）
        webView.customUserAgent = UserAgentOption.value(for: uaMode)

        // 清掉旧手势再重挂：SwiftUI 重挂（锁屏回来等）会新建 Coordinator，
        // 旧手势的 target 弱引用旧 Coordinator 已释放 → 点屏无反应；且 name 判断会让它跳过重挂。
        // ⚠️ 只删「我们自己 name 标记的」手势（barRevealSwipe / barRevealTap 及其前身 barRevealTap），
        //    绝不按类型删 UIScreenEdgePanGestureRecognizer：WebKit 原生的页内前进/后退手势就是同类实例
        //    （左边缘后退 + 右边缘前进，通常不止一个），按类型删会把「右滑后退」一起删掉——那正是本版要保住的交互。
        //    旧版自定义边缘手势无需清理：它挂在 PageState 缓存的 WebView 上，而缓存实例不跨 App 重启存活，
        //    升级后首次 makeUIView 拿到的都是新实例。
        for g in (webView.gestureRecognizers ?? [])
            where g.name == "barRevealSwipe" || g.name == "barRevealTap" {
            webView.removeGestureRecognizer(g)
        }

        // 2.6.1 删除「边缘右滑回主页」手势：书签首页右滑被送出 App 反直觉。
        // 后退完全交给 WebKit 自带返回手势（allowsBackForwardNavigationGestures 已开），
        // 回主页走底栏「主页」按钮/悬浮钮。

        if onBarReveal != nil {
            // 三指向下滑唤出底部导航栏（取代旧的「单击任意处」：后者太容易误触发、常遮挡内容）。
            // 三指是系统未占用的手势组合（系统三指只在文本编辑态用于拷贝/粘贴/撤销），
            // 浏览态零冲突；cancelsTouchesInView=false 保证不吞网页自身触摸。
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.barRevealed))
            swipe.name = "barRevealSwipe"
            swipe.numberOfTouchesRequired = 3
            swipe.direction = .down
            swipe.cancelsTouchesInView = false
            swipe.delegate = context.coordinator
            webView.addGestureRecognizer(swipe)
        }

        // （旧的「单击任意处唤出底栏」已删，2.6.1 起改为三指向下滑；见上方 barRevealSwipe）

        // 首次创建才加载初始 URL；复用实例（后台/分屏搬回）保留当前页面不重载
        let isFirstLoad = webView.url == nil
        if isFirstLoad, let url = URL(string: page.bookmark.urlString) {
            webView.load(URLRequest(url: url))
        }
        if isFirstLoad {
            webView.injectLoginFill()
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onBarReveal = onBarReveal
        webView.currentBookmark = page.bookmark

        // 只在值真的变了才写 WKWebView：每次 body 重算（如底栏显隐）都写 pageZoom / 跑 JS 会让网页闪一下、像刷新
        if context.coordinator.lastZoom != zoom {
            context.coordinator.lastZoom = zoom
            webView.pageZoom = zoom
        }

        let wantUA = UserAgentOption.value(for: uaMode)
        if webView.customUserAgent != wantUA {
            webView.customUserAgent = wantUA
            webView.reload()
        }

        if fontAdjust != 0, context.coordinator.lastFontAdjust != fontAdjust {
            context.coordinator.lastFontAdjust = fontAdjust
            let js = "document.documentElement.style.webkitTextSizeAdjust='\(100 + Int(fontAdjust))%';"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.page = page
        c.onBarReveal = onBarReveal
        return c
    }

    static let desktopUserAgent = UserAgentOption.desktopUA
}

extension WKWebView {
    var currentBookmark: Bookmark {
        get { objc_getAssociatedObject(self, &kBookmarkKey) as? Bookmark ?? Bookmark() }
        set { objc_setAssociatedObject(self, &kBookmarkKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
private var kBookmarkKey: UInt8 = 0

extension Notification.Name {
    static let launcherClearRefresh = Notification.Name("launcherClearRefresh")
    /// 网页内唤出底栏 → 通知底栏层（避免页面本体持有状态导致 WebView 跟着重绘）
    /// 2.6.1 起触发源改为「三指向下滑」（旧单击手势已删），通知名保持不变（分屏侧也复用）
    static let launcherPageTapped = Notification.Name("launcherPageTapped")
}

// 网页登录表单自动填充：页面加载后检测登录表单（input[type=password]），自动填入书签存的账密。
// 自动提交：填入后模拟回车/点登录按钮，sessionStorage 标记保证一次会话只提交一次（防账密错误死循环）。
// 隐私处理：已填的密码框强制 type=password 圆点显示（防个别网站设成 text 明文）。
// 注意：SplitScreen.swift 里的 SplitWebView 和本文件的 PageWebView 共用这个 extension。
extension WKWebView {
    func injectLoginFill() {
        let bm = currentBookmark
        guard !bm.loginUser.isEmpty || !bm.loginPass.isEmpty else { return }
        let autoSubmit = bm.autoSubmit
        let user = bm.loginUser
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let pass = bm.loginPass
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        // 多次尝试：SPA 页面登录框可能延迟渲染，1s/3s/6s 各试一次
        let js = """
        (function(){
          var user = '\(user)', pass = '\(pass)', autoSubmit = \(autoSubmit ? "true" : "false");
          function fill() {
            var pw = document.querySelector("input[type=password]");
            if (!pw) return false;
            var form = pw.form || pw.closest("form");
            var userEl = null;
            if (form) {
              userEl = form.querySelector("input[type=email], input[type=text], input[type=tel], input:not([type])");
            }
            if (!userEl && user) {
              // 无用户名时跳过用户名框检测，避免误命中页面其它输入框（如主面板的服务名框）
              userEl = document.querySelector("input[type=email], input[type=text], input[type=tel], input[name*=user i], input[name*=account i], input[name*=phone i], input[id*=user i]");
            }
            if (!userEl && user) {
              userEl = pw;
            }
            function setVal(el, v) {
              if (!el) return;
              var proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              var setter = Object.getOwnPropertyDescriptor(proto, "value").set;
              setter.call(el, v);
              el.dispatchEvent(new Event("input", {bubbles: true}));
              el.dispatchEvent(new Event("change", {bubbles: true}));
            }
            var changed = false;
            if (userEl && (userEl.value || "") !== user) { setVal(userEl, user); changed = true; }
            if ((pw.value || "") !== pass) { setVal(pw, pass); changed = true; }
            // 隐私：无论网站怎么设置，密码框强制按圆点显示
            if (pw.type !== "password") { try { pw.type = "password"; } catch(e) {} }
            pw.setAttribute("autocomplete", "off");
            if (!changed) return false;
            if (!autoSubmit) return true;
            // 自动提交：填入成功后模拟回车/点登录按钮（仅首次，sessionStorage 防账密错误死循环）
            if (!sessionStorage.getItem("__launcherAutofillSubmitted")) {
              sessionStorage.setItem("__launcherAutofillSubmitted", "1");
              setTimeout(function(){
                var fm = pw.form || pw.closest("form");
                if (fm) {
                  var btn = fm.querySelector("button[type=submit], input[type=submit]");
                  if (!btn) {
                    btn = Array.prototype.find.call(fm.querySelectorAll("button"), function(b){
                      return /登录|登 录|login|sign ?in|确定/i.test(b.textContent || "");
                    });
                  }
                  if (btn) { btn.click(); return; }
                  if (typeof fm.requestSubmit === "function") { fm.requestSubmit(); return; }
                }
                // 无 form 的页面（如激活台）：对密码框派发 Enter 键事件
                var opt = {key:"Enter", code:"Enter", keyCode:13, which:13, bubbles:true, cancelable:true};
                pw.dispatchEvent(new KeyboardEvent("keydown", opt));
                pw.dispatchEvent(new KeyboardEvent("keypress", opt));
                pw.dispatchEvent(new KeyboardEvent("keyup", opt));
              }, 150);
            }
            return changed;
          }
          [200, 1000, 3000, 6000].forEach(function(t){ setTimeout(fill, t); });
        })();
        """
        evaluateJavaScript(js, completionHandler: nil)
    }
}


// MARK: - 全屏/分屏页常驻「返回主页」胶囊（任何时候都可见可点，FAB 只是附加入口）

/// 底部导航栏浮层（自带显隐状态）
/// 关键：显隐状态只活在这一层，页面本体（含 WebView）完全不参与重算 —— 不再出现"刷一下"
struct PageBottomBarLayer: View {
    var mode: PageBottomBar.BarMode = .page
    var currentPage: PageState? = nil
    /// 「更多」/「查找页面」动作回调：宿主（FullscreenPage）开工具面板/查找条
    var onMore: (() -> Void)? = nil
    var onFind: (() -> Void)? = nil

    @State private var visible = true
    @State private var hideTask: DispatchWorkItem? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // 常驻挂载：隐藏 = 移出屏幕 + 透明 + 不响应点击，视图不销毁
            // 这样挂在本视图上的 sheet（多任务/分屏/设置等）不会被「自动隐藏」连带关掉
            PageBottomBar(mode: mode, currentPage: currentPage, onMore: onMore, onFind: onFind)
                // 页面层整层 ignoresSafeArea（LauncherApp），底栏会贴到屏幕绝对底部、
                // 比主页低一条小白条区域 → 手动补回底部安全区，与主页对齐
                .padding(.bottom, Self.bottomSafeInset)
                .offset(y: visible ? 0 : 140 + Self.bottomSafeInset)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
        }
        .animation(.easeInOut(duration: 0.2), value: visible)
        .onAppear { scheduleHide() }
        .onReceive(NotificationCenter.default.publisher(for: .launcherPageTapped)) { _ in
            visible = true
            scheduleHide()
        }
    }

    /// keyWindow 底部安全区高度（主页小白条 ≈34pt；home 模式不经过本层，天然避让）
    static var bottomSafeInset: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { visible = false }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}

/// 底部浮动导航栏（主页/全屏/分屏共用）：一级 3-4 钮，导入/导出/设置收进「更多」二级菜单
/// mode: .home 主页形态（无主页钮，带新增）；.page 网页形态（主页/多任务/分屏）
struct PageBottomBar: View {
    enum BarMode { case home, page }
    var mode: BarMode = .page
    /// 发起分屏时需要的当前页（page 模式下用）
    var currentPage: PageState? = nil
    /// 「更多」点击回调（page 模式：弹页面工具面板）；nil = 老行为（弹 Menu）
    var onMore: (() -> Void)? = nil
    /// 「查找页面」回调（面板里点「查找页面」时用）
    var onFind: (() -> Void)? = nil

    @EnvironmentObject var wm: WindowManager
    @EnvironmentObject var store: BookmarkStore
    @State private var showTaskSwitcher = false
    @State private var showSplitPicker = false
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var body: some View {
        HStack(spacing: 0) {
            if mode == .page {
                barButton("house", "主页") { wm.goHome() }
                barButton("square.on.square", "多任务") { showTaskSwitcher = true }
                barButton("rectangle.split.2x1", "分屏") { showSplitPicker = true }
            } else {
                barButton("square.on.square", "多任务") { showTaskSwitcher = true }
                barButton("plus", "新增") { showAdd = true }
            }
            if mode == .page, let more = onMore {
                // page 形态：「更多」= 页面工具面板（地址/查找/缩放/标识/分享/书签，主流浏览器式）
                barButton("ellipsis.circle", "更多") { more() }
            } else {
                // 主页形态：老 Menu（导入/导出/设置）
                Menu {
                    Button { showImporter = true } label: { Label("导入书签", systemImage: "square.and.arrow.down") }
                    ShareLink(item: store.exportURL(), preview: SharePreview("launcher-bookmarks.json")) {
                        Label("导出书签", systemImage: "arrow.up.doc")
                    }
                    Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 19))
                        Text("更多")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                }
                .tint(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // .regular（不是 .clear）：工具栏的标准玻璃材质，自带明/暗自适应底衬，
        // .primary 文字在任何网页底色上都可辨识；.clear 只该给悬浮钮这类媒体上方小控件。
        // 不加 tint —— 之前的蓝色 tint 既压不住底噪也让图标偏色。
        .launcherGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 玻璃可见区域整体接管触摸：没有它，玻璃边缘/字缝的点击会穿透到下面
        // （主页穿透=误开书签，网页穿透=误触页面内容）
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .sheet(isPresented: $showTaskSwitcher) {
            TaskSwitcherView()
                .environmentObject(wm)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSplitPicker) {
            // page 模式：当前页当上半屏；split 模式（分屏页内）：现上半屏重选下半屏
            if let page = currentPage {
                SplitPickerView(top: page.bookmark, topPage: page)
                    .environmentObject(wm)
                    .environmentObject(store)
            } else if let top = wm.splitTop {
                SplitPickerView(top: top, topPage: wm.splitTopPage)
                    .environmentObject(wm)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showAdd) {
            BookmarkEditView(store: store, bookmark: nil)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            // 导入书签：与主页原入口同一处理（security scoped + importFrom）
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                let n = store.importFrom(url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                importMessage = n >= 0 ? "成功导入 \(n) 个书签" : "导入失败：文件格式不对"
                showImportAlert = true
            }
        }
        .alert("导入结果", isPresented: $showImportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
