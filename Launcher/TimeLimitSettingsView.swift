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

    private var usedMin: Int { Int(tracker.secondsToday(for: bookmark.id) / 60) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(bookmark.name).fontWeight(.semibold)
                    Spacer()
                    Text("\u4eca\u65e5\u5df2\u7528 \(usedMin) \u5206\u949f")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("\u4e66\u7b7e")
            }

            Section {
                Toggle("\u6bcf\u65e5\u9650\u65f6", isOn: $enabled)
                if enabled {
                    HStack {
                        Text("\u6bcf\u65e5\u9650\u989d")
                        Spacer()
                        TextField("\u5206\u949f", value: $minutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .monospacedDigit()
                        Text("\u5206\u949f").foregroundStyle(.secondary)
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
                    Picker("\u8d85\u65f6\u89e3\u9501\u540e", selection: $mode) {
                        Text("\u6e05\u96f6\u91cd\u6765").tag(0)
                        Text("\u4eca\u5929\u4e0d\u518d\u9501").tag(1)
                        Text("\u52a0 15 \u5206\u949f").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("\u4f7f\u7528\u65f6\u95f4\u9650\u5236")
            } footer: {
                Text("\u8d85\u65f6\u540e\u65e0\u6cd5\u8bbf\u95ee\uff0c\u89e3\u9501\u9700\u7b97\u9898 + \u7b49\u5f85 5 \u5206\u949f + \u957f\u6309\u786e\u8ba4\u3002")
            }
        }
        .navigationTitle("\u4f7f\u7528\u65f6\u95f4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("\u53d6\u6d88") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("\u4fdd\u5b58") { save() }.fontWeight(.semibold)
            }
        }
        .onAppear {
            enabled = bookmark.timeLimitEnabled
            minutes = bookmark.dailyLimitMinutes
            mode = bookmark.unlockMode
        }
    }

    private func save() {
        guard let idx = store.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { dismiss(); return }
        var bm = store.bookmarks[idx]
        bm.timeLimitEnabled = enabled
        bm.dailyLimitMinutes = min(max(minutes, 1), 1440)
        bm.unlockMode = mode
        store.bookmarks[idx] = bm
        dismiss()
    }
}
