import SwiftUI

/// 使用时间统计 + 每日限额锁定
/// 存储：UserDefaults，按 bookmarkID + 日期 记累计秒数。
/// 故意不跟书签 json 走 —— 导出/导入书签不会带走使用数据，也不影响书签解码。
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    /// 当前在计时的书签 ID（前台全屏 1 个，或分屏 2 个）
    @Published private(set) var activeIDs: Set<UUID> = []

    /// 展示刷新信号：已用秒数或解锁状态变化时 +1。
    /// 进度条类视图（主页卡片进度线 / 多任务时间条 / 限时设置页）观察它实现实时刷新，
    /// 避免各视图自挂秒级定时器。计时只在有活跃书签时结算，空闲时不会空转触发刷新。
    @Published private(set) var usageRevision = 0

    private var sessionStart = Date()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        // 每 5 秒结算一次（时间戳差值，不逐秒累加），兼顾精度与省电
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.flush()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        let center = NotificationCenter.default
        // 进后台 / 退出时立即结算，避免丢最后几秒
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.flush() })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.flush() })
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 计时切换

    func setActive(_ ids: Set<UUID>) {
        flush()
        activeIDs = ids
        sessionStart = Date()
    }

    // MARK: - 结算

    private func flush() {
        guard !activeIDs.isEmpty else { return }
        let elapsed = Date().timeIntervalSince(sessionStart)
        sessionStart = Date()
        guard elapsed > 0 else { return }
        for id in activeIDs { add(elapsed, to: id) }
        // 落地成功 → 发刷新信号（此时已用秒数真的变了，进度条/时间条据此重算）
        usageRevision &+= 1
    }

    private func add(_ seconds: Double, to id: UUID) {
        let key = Self.usageKey(for: id)
        let cur = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(cur + seconds, forKey: key)
    }

    // MARK: - 查询

    func secondsToday(for id: UUID) -> Double {
        UserDefaults.standard.double(forKey: Self.usageKey(for: id))
    }

    /// 是否被锁：启用限制 && 今日已用 ≥ 限额 && 未被"今天不再锁"
    func isLocked(_ bm: Bookmark) -> Bool {
        guard bm.timeLimitEnabled, bm.dailyLimitMinutes > 0 else { return false }
        if unlockedToday(bm.id) { return false }
        return secondsToday(for: bm.id) >= Double(bm.dailyLimitMinutes) * 60
    }

    // MARK: - 解锁后行为

    func resetToday(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: Self.usageKey(for: id))
        UsageBadgeCache.shared.invalidate(id)
        usageRevision &+= 1
    }

    func markUnlockedToday(_ id: UUID) {
        UserDefaults.standard.set(true, forKey: Self.unlockedKey(for: id))
        UsageBadgeCache.shared.invalidate(id)
        usageRevision &+= 1
    }

    func unlockedToday(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: Self.unlockedKey(for: id))
    }

    /// 加时：把"已用"设为 limit - minutes，使解锁后还能再用 minutes 分钟
    func addBonusMinutes(_ minutes: Double, to id: UUID, limitMinutes: Int) {
        let target = max(0, Double(limitMinutes) - minutes) * 60
        UserDefaults.standard.set(target, forKey: Self.usageKey(for: id))
        UsageBadgeCache.shared.invalidate(id)
        usageRevision &+= 1
    }

    // MARK: - keys（按天分桶，跨天自动重置）

    private static func usageKey(for id: UUID) -> String {
        "usage.\(id.uuidString).\(dayFormatter.string(from: Date()))"
    }

    private static func unlockedKey(for id: UUID) -> String {
        "unlocked.\(id.uuidString).\(dayFormatter.string(from: Date()))"
    }
}
