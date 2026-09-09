import SwiftUI

/// 全屏/悬浮窗口状态管理（App 级）
final class WindowManager: ObservableObject {
    @Published var pages: [PageState] = [] {
        didSet { persistPages() }
    }
    @Published var fullscreenID: UUID? {
        didSet { persistPages() }
    }
    @Published var floatingID: UUID?
    /// 悬浮窗功能开关：代码保留，暂不显示
    @Published var showFloating = false
    /// 分屏状态（经悬浮钮「分屏」进入）
    @Published var splitTop: Bookmark?
    @Published var splitBottom: Bookmark?
    /// 对应半屏的后台 PageState（有则复用常驻 WebView）
    @Published var splitTopPage: PageState?
    @Published var splitBottomPage: PageState?
    @Published var floatingPos: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 90, y: 160)
    @Published var floatingWidth: CGFloat = 120
    // 默认高宽比 = 屏幕比例
    @Published var floatingHeight: CGFloat = 120 * (UIScreen.main.bounds.height / UIScreen.main.bounds.width)

    /// 打开书签：已在列表里 → 直接放大到全屏；否则新开（超过 4 个关掉最早的未显示页）
    func open(_ bm: Bookmark) {
        if let page = pages.first(where: { $0.bookmark.id == bm.id }) {
            fullscreenID = page.id
            return
        }
        if pages.count >= 4 {
            // 优先关悬浮窗里的（不可见且可重建），再关最早的其它未显示页
            if let fid = floatingID {
                pages.removeAll { $0.id == fid }
                floatingID = nil
            }
            if pages.count >= 4,
               let victim = pages.first(where: { $0.id != fullscreenID }) {
                pages.removeAll { $0.id == victim.id }
            }
        }
        let page = PageState(bm)
        pages.append(page)
        fullscreenID = page.id
    }

    /// 回主页：只关全屏层，页面状态保留
    func goHome() {
        fullscreenID = nil
    }

    /// 当前全屏页缩成悬浮窗（唯一入口，手动触发）
    func minimizeToFloating() {
        guard let fs = fullscreenID else { return }
        if let fid = floatingID {
            pages.removeAll { $0.id == fid }   // 只允许一个悬浮窗
        }
        floatingID = fs
        fullscreenID = nil
    }

    /// 点悬浮窗：全屏 ↔ 悬浮互换（WebView 不重建，浏览状态保留）
    func swap() {
        let f = floatingID
        floatingID = fullscreenID
        fullscreenID = f
    }

    func closePage(_ id: UUID) {
        if let idx = pages.firstIndex(where: { $0.id == id }) {
            let bmID = pages[idx].bookmark.id
            pages.remove(at: idx)
            // 该页正在分屏里 → 同步关掉那半屏（转正另一半），避免僵尸半屏
            if splitTop?.id == bmID || splitBottom?.id == bmID {
                let survivor = splitTop?.id == bmID ? splitBottom : splitTop
                splitTop = nil
                splitBottom = nil
                splitTopPage = nil
                splitBottomPage = nil
                if let s = survivor { open(s) }
            }
        }
        if fullscreenID == id { fullscreenID = nil }
        if floatingID == id { floatingID = nil }
    }

    /// 把某后台页设为分屏一半：top=true 设为上半屏。已在分屏里则换掉那半
    func setPageForSplit(_ bm: Bookmark, top: Bool, page: PageState? = nil) {
        if top {
            splitTop = bm
            splitTopPage = page
        } else {
            splitBottom = bm
            splitBottomPage = page
        }
    }

    /// 两半都齐 → true（供调用方判断能否直接进分屏）
    var splitReady: Bool { splitTop != nil && splitBottom != nil }

    // MARK: - 页面会话持久化（App 重启后恢复多任务页面）
    private static let pagesKey = "openPageBookmarkIDs"
    private static let fullscreenKey = "openFullscreenBookmarkID"

    private func persistPages() {
        let ids = pages.compactMap { $0.bookmark.id.uuidString }
        UserDefaults.standard.set(ids, forKey: Self.pagesKey)
        let fsID = fullscreenID.flatMap { fid in
            pages.first { $0.id == fid }?.bookmark.id.uuidString
        }
        UserDefaults.standard.set(fsID, forKey: Self.fullscreenKey)
    }

    /// 内存警告：释放后台页 WebView，保住前台正在用的那个（避免前台被系统回收导致"突然刷新"）
    func releaseBackgroundWebViews() {
        for page in pages where page.id != fullscreenID {
            page.captureSnapshot()      // 先留张图，切回来不会白屏
            page.releaseWebView()
        }
    }

    /// 打开多任务时刷新全部页面快照；未挂载过的页面先补载初始 URL
    func refreshAllSnapshots() {
        for page in pages {
            // force：即使该页正在前台（snapshotSuspended）也要抓，切换器要显示实时内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                page.captureSnapshot(force: true)
            }
            // 已释放（内存紧张时卸掉的后台页）→ 重新挂载并重载一次，保证卡片有内容
            if page.released {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let url = URL(string: page.bookmark.urlString) {
                        page.webView.load(URLRequest(url: url))
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    page.captureSnapshot(force: true)
                }
            }
        }
    }

    /// App 启动时调用：按保存的书签 ID 恢复后台页面
    func restorePages(store: BookmarkStore) {
        guard pages.isEmpty, let ids = UserDefaults.standard.stringArray(forKey: Self.pagesKey), !ids.isEmpty else { return }
        let uuids = ids.compactMap { UUID(uuidString: $0) }
        for id in uuids {
            if let bm = store.bookmarks.first(where: { $0.id == id }) {
                pages.append(PageState(bm))
            }
        }
        if let fsUUID = UserDefaults.standard.string(forKey: Self.fullscreenKey).flatMap({ UUID(uuidString: $0) }),
           let page = pages.first(where: { $0.bookmark.id == fsUUID }) {
            fullscreenID = page.id
        }
        if !pages.isEmpty && fullscreenID == nil {
            UserDefaults.standard.removeObject(forKey: Self.fullscreenKey)
        }
    }
}
