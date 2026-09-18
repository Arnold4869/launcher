import SwiftUI

// MARK: - 使用时间设置（从多任务长按菜单直达，只管时间）

struct TimeLimitSettingsView: View {
    @ObservedObject var store: BookmarkStore
    let bookmark: Bookmark

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tracker = UsageTracker.shared

    @State private var enabled: Bool = false
    @State private var minutes: Int = 30
    @State private var mode: Int = 0
    @State private var bonusMinutes: Int = 15

    private var usedMin: Int { Int(tracker.secondsToday(for: bookmark.id) / 60) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(bookmark.name).fontWeight(.semibold)
                    Spacer()
                    Text("今日已用 \(usedMin) 分钟")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("书签")
            }

            Section {
                Toggle("每日限时", isOn: $enabled)
                if enabled {
                    HStack {
                        Text("每日限额")
                        Spacer()
                        TextField("分钟", value: $minutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .monospacedDigit()
                        Text("分钟").foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { m in
                                Button { minutes = m } label: {
                                    Text("\(m)")
                                        .font(.subheadline.monospacedDigit())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(minutes == m ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                        .foregroundStyle(minutes == m ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Picker("超时解锁后", selection: $mode) {
                        Text("清零重来").tag(0)
                        Text("今天不再锁").tag(1)
                        Text("加时").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if mode == 2 {
                        HStack {
                            Text("每次解锁加时")
                            Spacer()
                            TextField("分钟", value: $bonusMinutes, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .monospacedDigit()
                            Text("分钟").foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { m in
                                    Button { bonusMinutes = m } label: {
                                        Text("\(m)")
                                            .font(.subheadline.monospacedDigit())
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(bonusMinutes == m ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                            .foregroundStyle(bonusMinutes == m ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("使用时间限制")
            } footer: {
                Text("超时后无法访问，解锁需算题 + 等待 5 分钟 + 长按确认。")
            }
        }
        .navigationTitle("使用时间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }.fontWeight(.semibold)
            }
        }
        .onAppear {
            enabled = bookmark.timeLimitEnabled
            minutes = bookmark.dailyLimitMinutes
            mode = bookmark.unlockMode
            bonusMinutes = bookmark.unlockBonusMinutes
        }
        // 已用秒数每 5 秒落地 → 「今日已用 X 分钟」跟着走（2.6.3）
        .onChange(of: tracker.usageRevision) { _ in }
    }

    private func save() {
        guard let idx = store.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { dismiss(); return }
        var bm = store.bookmarks[idx]
        bm.timeLimitEnabled = enabled
        bm.dailyLimitMinutes = min(max(minutes, 1), 1440)
        bm.unlockMode = mode
        bm.unlockBonusMinutes = min(max(bonusMinutes, 1), 1440)
        store.bookmarks[idx] = bm
        dismiss()
    }
}
