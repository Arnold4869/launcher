import SwiftUI

/// 锁定解锁页：数学题 → 等 5 分钟 → 长按倒计时，两关都过才解锁。
/// 隐藏跳过：先过第一关（算对答案），再连点「第一步 · 算一道题」标题 10 次，
///             接着连点「第二步 · 等 5 分钟」标题 10 次，即可跳过等待（顺序不可颠倒，可多点）。
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
    @State private var wrongAnswer = false
    @FocusState private var answerFocused: Bool

    // 第二关：5 分钟等待（App 内计时，退出即重置）
    @State private var waitRemaining: TimeInterval = 5 * 60
    @State private var waitPassed = false
    private let waitTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 第三关：长按倒计时
    @State private var holdProgress: Double = 0
    @State private var holdDone = false
    @State private var holdTimer: Timer?

    // 隐藏跳过：先连点「第一步」标题 10 次 → 再连点「第二步」标题 10 次
    @State private var stage1Taps = 0
    @State private var stage2Taps = 0
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
            stageCard(title: "第一步 · 算一道题", done: mathPassed, secretTag: 1) {
                Text("\(a) × \(b) = ?")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                TextField("答案", text: $answer)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.center)
                    .focused($answerFocused)
                    .submitLabel(.done)
                    .onSubmit { checkMath() }
                if wrongAnswer {
                    Text("答案不对，再算一次")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 12) {
                    if answerFocused {
                        Button("收起键盘") { answerFocused = false }
                            .buttonStyle(.bordered)
                    }
                    Button("确认") { checkMath() }
                        .buttonStyle(.borderedProminent)
                }
            }

            // 第二关：等 5 分钟
            stageCard(title: "第二步 · 等 5 分钟", done: waitPassed, secretTag: 2) {
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
        .onAppear {
            a = Int.random(in: 7...99); b = Int.random(in: 7...99)
        }
    }

    // MARK: - 关卡视图

    private func stageCard<Content: View>(title: String, done: Bool, secretTag: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let tag = secretTag else { return }
                secretStageTap(tag)
            }
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 逻辑

    private func checkMath() {
        guard Int(answer) == a * b else {
            wrongAnswer = true
            return
        }
        wrongAnswer = false
        answerFocused = false          // 收起数字键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    private func secretStageTap(_ tag: Int) {
        guard mathPassed else { return }          // 第一关过了才认
        if tag == 1 {
            if stage2Taps < 10 { stage1Taps += 1 }
            return
        }
        // 第二步：必须先点满第一步 10 次，再点第二步 10 次
        guard stage1Taps >= 10 else { return }
        stage2Taps += 1
        if stage2Taps >= 10 && !skipUsed {
            skipUsed = true
            waitPassed = true
            stage1Taps = 0
            stage2Taps = 0
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
