import SwiftUI
import WebKit

// MARK: - 页面查找条（「更多」→ 查找页面 后从底部升起，压在底栏之上）
//
// 逻辑对齐主流浏览器：输入即定位到第一个匹配并显示命中数，向左/右箭头步进循环查找，
// × 关闭并清掉选中高亮。键盘弹起时整条跟着上移（跟随键盘安全区）。

struct PageFindBar: View {
    let wv: WKWebView
    @Binding var isPresented: Bool

    @State private var term = ""
    @State private var count: Int? = nil
    @State private var unsupported = false
    @State private var noMatch = false
    @State private var searchTask: DispatchWorkItem?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("查找页面", text: $term)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { runStep(backwards: false) }
                .onChange(of: term) { _ in scheduleSearch() }

            // 命中数（不支持逐级查找时如实标注）
            if let c = count {
                Text(unsupported ? "共\(c)处" : "\(c)处")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(noMatch && c == 0 ? Color.red : .secondary)
                    .fixedSize()
            }

            Button { runStep(backwards: true) } label: {
                Image(systemName: "chevron.up").font(.footnote.weight(.semibold))
            }
            .disabled(term.isEmpty)
            .foregroundStyle(term.isEmpty ? Color.secondary : Color.primary)

            Button { runStep(backwards: false) } label: {
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
            }
            .disabled(term.isEmpty)
            .foregroundStyle(term.isEmpty ? Color.secondary : Color.primary)

            Button { close() } label: {
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .launcherGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .onAppear { focused = true }
        .onDisappear { PageFind.clear(in: wv) }
    }

    /// 输入防抖 0.35s：边打字边查会让大页面卡顿
    private func scheduleSearch() {
        searchTask?.cancel()
        let t = term
        guard !t.isEmpty else {
            count = nil
            noMatch = false
            PageFind.clear(in: wv)
            return
        }
        let task = DispatchWorkItem { [weak wv] in
            guard let wv else { return }
            PageFind.count(t, in: wv) { c in
                count = c
                noMatch = (c == 0)
            }
            PageFind.step(t, backwards: false, in: wv) { ok, unsup in
                unsupported = unsup
                if !ok { noMatch = true }
            }
        }
        searchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func runStep(backwards: Bool) {
        guard !term.isEmpty else { return }
        PageFind.step(term, backwards: backwards, in: wv) { ok, unsup in
            unsupported = unsup
            noMatch = !ok
        }
    }

    private func close() {
        PageFind.clear(in: wv)
        focused = false
        isPresented = false
    }
}
