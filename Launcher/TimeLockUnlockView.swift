import SwiftUI

/// 锁定解锁页：数学题 → 等 5 分钟 → 长按倒计时，两关都过才解锁。
/// 隐藏跳过：左上角连点 10 次 + 右上角连点 10 次，即可跳过 5 分钟等待。
/// 退出 app 重进后，5 分钟等待重新计时（等待用 App 内计时器，不落盘）。
struct TimeLockUnlockView: View {
    let bookmark: Bookmark
    var onUnlock: (Int) -> Void   // 回调解锁方式（unlockMode）
    @Environment(\.dismiss) private var dismiss

    // 第一关：数学题
    @State private var a = 0
    @State private var b = 0
    @State private var answer = ""
    @State private var mathPassed = false

    // 第二关：5 分钟等待（App 内计时，退出即重置）
    @State private var waitRemaining: TimeInterval = 5 * 60
    @State private var waitPassed = false
    private let waitTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 第三关：长按倒计时
    @State private var holdProgress: Double = 0
    @State private var holdDone = false
    @State private var holdTimer: Timer?

    // 隐藏跳过
    @State private var topLeftTaps = 0
    @State private var topRightTaps = 0
    @State private var skipUsed = false

    var body: some View {
        VStack(spacing: 24) {
            Text("「\(bookmark.name)」已到今日限额")
                .font(.title3.bold())
            Text("今日已用 \(Int(UsageTracker.shared.secondsToday(for: bookmark.id) / 60)) 分钟")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // 第一关：数学题
            stageCard(title: "第一步 · 算一道题", done: mathPassed) {
                Text("\(a) × \(b) = ?")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                TextField("答案", text: $answer)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.center)
                Button("确认") { checkMath() }
                    .buttonStyle(.borderedProminent)
            }

            // 第二关：等 5 分钟
            stageCard(title: "第二步 · 等 5 分钟", done: waitPassed) {
                if waitPassed {
                    Label("时间到", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("还剩 \(format(waitRemaining))")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .onReceive(waitTimer) { _ in
                            if mathPassed && !waitPassed {
                                waitRemaining -= 1
                                if waitRemaining <= 0 { waitPassed = true }
                            }
                        }
                }
            }

            // 第三关：长按确认（按住 3 秒）
            stageCard(title: "第三步 · 长按确认", done: holdDone) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 6)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)
                        .animation(.linear(duration: 0.1), value: holdProgress)
                    Text(holdDone ? "完成" : "按住 3 秒")
                        .font(.headline)
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard mathPassed && waitPassed, !holdDone else { return }
                            startHold()
                        }
                        .onEnded { _ in cancelHold() }
                )
            }

            Spacer()

            Button("返回") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
        // 隐藏跳过：左上角 + 右上角各连点 10 次
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 80, height: 80).contentShape(Rectangle())
                .onTapGesture { secretTap(&topLeftTaps, other: topRightTaps, isLeft: true) }
        }
        .overlay(alignment: .topTrailing) {
            Color.clear.frame(width: 80, height:80).contentShape(Rectangle())
                .onTapGesture { secretTap(&topRightTaps, other: topLeftTaps, isLeft: false) }
        }
        .onAppear {
            a = Int.random(in: 7...99); b = Int.random(in: 7...99)
        }
    }

    // MARK: - 关卡视图

    private func stageCard<Content: View>(title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 逻辑

    private func checkMath() {
        guard Int(answer) == a * b else { return }
        mathPassed = true
        waitRemaining = 5 * 60
        if skipUsed { waitPassed = true }
    }

    private func startHold() {
        guard holdTimer == nil else { return }
        holdProgress = 0
        let start = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(start)
            holdProgress = min(elapsed / 3.0, 1.0)
            if elapsed >= 3.0 {
                holdTimer?.invalidate()
                holdTimer = nil
                if mathPassed && waitPassed {
                    holdDone = true
                    finish()
                }
            }
        }
        if let t = holdTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdProgress = 0
    }

    private func finish() {
        let mode = bookmark.unlockMode
        onUnlock(mode)
        dismiss()
    }

    private func secretTap(_ counter: inout Int, other: Int, isLeft: Bool) {
        guard mathPassed else { return }
        counter += 1
        if counter >= 10 && other >= 10 {
            skipUsed = true
            waitPassed = true
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
