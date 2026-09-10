import SwiftUI

// MARK: - 多任务卡片上的使用时间条

/// 已用 / 剩余 + 进度条；锁定态显示锁图标
struct UsageBadge: View {
    let bookmark: Bookmark
    @ObservedObject private var tracker = UsageTracker.shared

    private var usedSec: Double { tracker.secondsToday(for: bookmark.id) }
    private var limitSec: Double { Double(bookmark.dailyLimitMinutes) * 60 }
    private var remainSec: Double { max(0, limitSec - usedSec) }
    private var locked: Bool { tracker.isLocked(bookmark) }
    private var progress: Double { limitSec > 0 ? min(1, usedSec / limitSec) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: locked ? "lock.fill" : "hourglass")
                    .font(.system(size: 9, weight: .semibold))
                Text(locked ? "已超时" : "\u5269 \(Int(ceil(remainSec / 60))) \u5206\u949f")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                Spacer()
                Text("\u5df2\u7528 \(Int(usedSec / 60)) / \(bookmark.dailyLimitMinutes)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(locked ? .red : .secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(locked ? Color.red : (progress > 0.8 ? Color.orange : Color.accentColor))
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
    }
}
