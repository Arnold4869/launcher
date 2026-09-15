import SwiftUI

// MARK: 锁定状态轻量缓存

/// 主页卡片角标在滚动时每帧都会查锁定状态，直接读 UserDefaults 太慢。
/// 这里按「书签ID + 当日已用秒数量级」缓存，避免滚动掉帧。
/// 数值来源仍是 UsageTracker（唯一真源），这里只做查询加速。
final class UsageBadgeCache {
    static let shared = UsageBadgeCache()

    /// 缓存：书签ID -> (当时已用秒数, 是否锁定)
    private var cache: [UUID: (used: Double, locked: Bool)] = [:]
    
    // 确保线程安全
    private let lock = NSLock()

    private init() {}

    /// 查锁定状态 + 限时进度（一次查缓存、一次查 UserDefaults，合二为一）
    /// 主页玻璃卡（2.6.0）同时要 locked 和 progress，别分开调 isLocked/progress（两次缓存查找）。
    /// - Returns: (progress, locked)；书签未启用限额返回 nil
    func progressWithLock(_ bm: Bookmark) -> (progress: Double, locked: Bool)? {
        guard bm.timeLimitEnabled, bm.dailyLimitMinutes > 0 else { return nil }
        let used = UsageTracker.shared.secondsToday(for: bm.id)
        let limit = Double(bm.dailyLimitMinutes) * 60

        lock.lock()
        if let hit = cache[bm.id], abs(hit.used - used) < 1 {
            lock.unlock()
            return (min(1, used / limit), hit.locked)
        }
        lock.unlock()

        let locked = UsageTracker.shared.isLocked(bm)
        refreshCache(bm: bm, used: used, locked: locked)
        return (min(1, used / limit), locked)
    }

    /// 查锁定状态：已用秒数没变就直接返回缓存结果
    func isLocked(_ bm: Bookmark) -> Bool {
        guard bm.timeLimitEnabled else { return false }
        let used = UsageTracker.shared.secondsToday(for: bm.id)

        lock.lock()
        if let hit = cache[bm.id], abs(hit.used - used) < 1 {
            lock.unlock()
            return hit.locked
        }
        lock.unlock()

        let locked = UsageTracker.shared.isLocked(bm)
        refreshCache(bm: bm, used: used, locked: locked)
        return locked
    }

    /// 兼容旧调用：只查进度（主页玻璃卡请改用 progressWithLock 一次拿两个值）
    func progress(_ bm: Bookmark) -> Double? {
        progressWithLock(bm)?.progress
    }

    private func refreshCache(bm: Bookmark, used: Double, locked: Bool) {
        lock.lock()
        cache[bm.id] = (used, locked)
        lock.unlock()
    }

    /// 使用数据被重置/解锁后调用，清掉缓存
    func invalidate(_ id: UUID? = nil) {
        lock.lock()
        if let id {
            cache.removeValue(forKey: id)
        } else {
            cache.removeAll()
        }
        lock.unlock()
    }
}
