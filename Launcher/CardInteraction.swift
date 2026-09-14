import SwiftUI
import UIKit

// MARK: - 卡片交互层（UIKit 实现）
//
// 为什么不用 SwiftUI 手势：iOS 18/26 下挂在横向 ScrollView 子视图上的 DragGesture 会抢走
// 滚动，且 SwiftUI 无法让手势主动 fail（simultaneousGesture + 轴向锁实测救不回来，2.3.0 翻车）。
// UIKit 可以：自定义 UIPanGestureRecognizer 判向为横向时把 state 置 .failed，ScrollView 的
// pan 立刻接管 → 横向滑动照常翻卡片，纵向拖动仍归卡片（上滑关闭）。
//
// 这一个 UIView 承担三件事：点按、长按菜单、纵向拖动，避免多层手势互相抢。

struct CardInteractionLayer: UIViewRepresentable {
    var onTap: () -> Void
    /// 纵向拖动位移（dy，负 = 向上）
    var onVerticalChanged: (CGFloat) -> Void
    var onVerticalEnded: (CGFloat) -> Void
    /// 长按菜单项
    var menuItems: () -> [UIMenuElement]

    func makeUIView(context: Context) -> CardInteractionView {
        let v = CardInteractionView()
        v.onTap = onTap
        v.onVerticalChanged = onVerticalChanged
        v.onVerticalEnded = onVerticalEnded
        v.menuItems = menuItems
        v.install()
        return v
    }

    func updateUIView(_ v: CardInteractionView, context: Context) {
        v.onTap = onTap
        v.onVerticalChanged = onVerticalChanged
        v.onVerticalEnded = onVerticalEnded
        v.menuItems = menuItems
    }
}

final class CardInteractionView: UIView, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
    var onTap: () -> Void = {}
    var onVerticalChanged: (CGFloat) -> Void = { _ in }
    var onVerticalEnded: (CGFloat) -> Void = { _ in }
    var menuItems: () -> [UIMenuElement] = { [] }

    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        backgroundColor = .clear

        // 点按
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)

        // 纵向拖动：横向自动 fail 让位给 ScrollView
        let pan = DirectionalPan()
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.onVerticalChanged = { [weak self] dy in self?.onVerticalChanged(dy) }
        pan.onVerticalEnded = { [weak self] dy in self?.onVerticalEnded(dy) }
        addGestureRecognizer(pan)

        // 长按菜单（原生 UIContextMenu，观感与 SwiftUI .contextMenu 一致）
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @objc private func handleTap() { onTap() }

    // 与 ScrollView 的 pan 共存；我们的识别器横向会自己失败，不阻塞滚动
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: 长按菜单
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let items = menuItems()
        guard !items.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: "", children: items)
        }
    }
}

// MARK: - 只认纵向的 pan：横向立即失败，把滚动还给横向 ScrollView

final class DirectionalPan: UIPanGestureRecognizer {
    var onVerticalChanged: (CGFloat) -> Void = { _ in }
    var onVerticalEnded: (CGFloat) -> Void = { _ in }

    private var decided = false
    private var vertical = false
    private var startPoint: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        decided = false
        vertical = false
        startPoint = touches.first?.location(in: view) ?? .zero
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let point = touches.first?.location(in: view) else { return }
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y

        if !decided {
            // 等位移足够再判向，避免抖动误判
            guard abs(dx) >= 12 || abs(dy) >= 12 else { return }
            decided = true
            vertical = abs(dy) > abs(dx)
            if !vertical {
                // 横向 → 主动失败，ScrollView 的 pan 接管（能左右滑动看其它卡片）
                state = .failed
                return
            }
        }
        guard vertical else { return }
        onVerticalChanged(dy)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let wasVertical = vertical && decided
        let point = touches.first?.location(in: view) ?? startPoint
        let dy = point.y - startPoint.y
        super.touchesEnded(touches, with: event)
        if wasVertical, state == .ended || state == .changed {
            onVerticalEnded(dy)
        }
        decided = false
        vertical = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        decided = false
        vertical = false
    }
}
