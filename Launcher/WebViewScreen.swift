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
            // 【自定义玻璃 → 原生 glassEffect/.regular】悬浮窗标题栏=导航层控件
            .launcherGlass(.regular, in: RoundedRectangle(cornerRadius: 10), interactive: false)
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
        // 悬浮窗本体是"内容页"（网页缩略图），不整块 glassEffect——只标题栏玻璃（上面已加）。
        // 这里仅保留半透明黑底 + 阴影做容器边界，符合"内容本体禁止 glassEffect"约束。
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
        }
        .overlay {
            // 可拖动 + 自动吸边隐藏的悬浮钮（位置持久化，跟主屏共用）
            FloatingMenuButton(expanded: expanded, onToggle: {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            })
            .onReceive(NotificationCenter.default.publisher(for: .fabActionHome)) { _ in
                expanded = false; wm.goHome()
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
                    // 【系统原生玻璃 → .glassProminent】Form 内主行动按钮
                    Button("完成") { saveAndDismiss() }
                        .fontWeight(.semibold)
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
        var clearRefreshObserver: NSObjectProtocol? = nil

        deinit {
            if let obs = clearRefreshObserver { NotificationCenter.default.removeObserver(obs) }
        }

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation) {
            webView.injectLoginFill()
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
        webView.injectLoginFill()
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

extension Notification.Name {
    static let launcherClearRefresh = Notification.Name("launcherClearRefresh")
}

// 网页登录表单自动填充：页面加载后检测登录表单（input[type=password]），自动填入书签存的账密。
// 自动提交：填入后模拟回车/点登录按钮，sessionStorage 标记保证一次会话只提交一次（防账密错误死循环）。
// 隐私处理：已填的密码框强制 type=password 圆点显示（防个别网站设成 text 明文）。
// 注意：SplitScreen.swift 里的 SplitWebView 和本文件的 PageWebView 共用这个 extension。
extension WKWebView {
    func injectLoginFill() {
        let bm = currentBookmark
        guard !bm.loginUser.isEmpty || !bm.loginPass.isEmpty else { return }
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
          var user = '\(user)', pass = '\(pass)';
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
