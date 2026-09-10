import SwiftUI

/// 全屏/悬浮窗口状态管理（App 级）
final class WindowManager: ObservableObject {
    @Published var pages: [PageState] = [] {
        didSet { persistPages() }
    }
    /// 被锁定（超时）的书签：非 nil 时顶层弹解锁页
    @Published var lockedBookmark: Bookmark?
    @Published var fullscreenID: UUID? {
        didSet {
            // 维护 isForeground 标记：只有当前全屏页是"前台"，其余全标后台。
            // 前台页跳过截图（阅读不卡），后台页允许截图。
            for page in pages {
                page.isForeground = (page.id == fullscreenID)
            }
            updateUsageActive()
            persistPages()
        }
    }
    /// 分屏状态（经悬浮钮「分屏」进入）
    @Published var splitTop: Bookmark? { didSet { updateUsageActive() } }
    @Published var splitBottom: Bookmark? { didSet { updateUsageActive() } }
    /// 对应半屏的后台 PageState（有则复用常驻 WebView）
    @Published var splitTopPage: PageState?
    @Published var splitBottomPage: PageState?
    private var usageTimer: Timer?

    init() {
        // 每 5 秒检查一次当前活跃书签是否超限（超限踢回主页 + 弹解锁）
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.enforceLimits()
        }
        if let t = usageTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// 打开书签：已在列表里 → 直接放大到全屏；否则新开（超过 4 个关掉最早的未显示页）
    func open(_ bm: Bookmark) {
        // 限时锁定：超时则拦截，弹解锁页（不打开页面）
        if UsageTracker.shared.isLocked(bm) {
            lockedBookmark = bm
            return
        }
        if let page = pages.first(where: { $0.bookmark.id == bm.id }) {
            fullscreenID = page.id
            return
        }
        if pages.count >= 4 {
            // 关掉最早的未显示页
            if let victim = pages.first(where: { $0.id != fullscreenID }) {
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

    // MARK: - 使用时间统计

    /// 维护活跃计时书签：前台全屏 1 个 + 分屏两半
    private func updateUsageActive() {
        var ids = Set<UUID>()
        if let fs = fullscreenID, let page = pages.first(where: { $0.id == fs }) {
            ids.insert(page.bookmark.id)
        }
        if let t = splitTop { ids.insert(t.id) }
        if let b = splitBottom { ids.insert(b.id) }
        UsageTracker.shared.setActive(ids)
    }

    /// 每 5 秒：检查活跃书签是否超限。超限 → 踢回主页 + 弹解锁页
    private func enforceLimits() {
        // 正在解锁中不再重复弹
        guard lockedBookmark == nil else { return }
        if let fs = fullscreenID, let page = pages.first(where: { $0.id == fs }),
           UsageTracker.shared.isLocked(page.bookmark) {
            kickOut(page.bookmark)
            return
        }
        if let t = splitTop, UsageTracker.shared.isLocked(t) { kickOut(t); return }
        if let b = splitBottom, UsageTracker.shared.isLocked(b) { kickOut(b); return }
    }

    private func kickOut(_ bm: Bookmark) {
        // 关掉该书签的全屏/分屏，回主页
        fullscreenID = nil
        if splitTop?.id == bm.id { splitTop = nil; splitTopPage = nil }
        if splitBottom?.id == bm.id { splitBottom = nil; splitBottomPage = nil }
        lockedBookmark = bm
    }

    /// 解锁通过后按 unlockMode 生效
    func applyUnlock(_ bm: Bookmark, mode: Int) {
        switch mode {
        case 1: UsageTracker.shared.markUnlockedToday(bm.id)   // 今天不再锁
        case 2: UsageTracker.shared.addBonusMinutes(15, to: bm.id, limitMinutes: bm.dailyLimitMinutes)  // 加 15 分钟
        default: UsageTracker.shared.resetToday(bm.id)         // 清零重来
        }
        lockedBookmark = nil
        UsageBadgeCache.shared.invalidate(bm.id)
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
        // 打开切换器 = 切后台，前台标记先清掉，否则当前页会被 captureSnapshot 跳过、预览图永远是旧的
        for page in pages { page.isForeground = false }
        for page in pages {
            // 打开切换器时补抓一次，兜底全屏期间可能漏掉的
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                page.captureSnapshot()
            }
            // 已释放（内存紧张时卸掉的后台页）→ 重新挂载并重载，多档重试抓快照
            if page.released {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let url = URL(string: page.bookmark.urlString) {
                        page.webView.load(URLRequest(url: url))
                    }
                }
                // 页面加载耗时不定：多档重试，空白检测会挡住还没渲染完的图
                for delay in [1.2, 2.5, 4.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak page] in
                        page?.captureSnapshot()
                    }
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
