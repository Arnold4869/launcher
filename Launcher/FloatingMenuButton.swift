import SwiftUI

// MARK: - 可拖动 + 自动吸附隐藏的悬浮主钮
//
// 行为：
// - 单击 = 展开菜单；拖动 = 移动位置（松手吸边）
// - 靠近左/右边缘时自动吸到该侧；吸边后只露 6pt 小耳朵，轻点耳朵弹出
// - 位置持久化（AppStorage），全屏页和分屏页共用一个位置
// - 拖动/吸边跟随用 spring 动画，玻璃样式不变

struct FloatingMenuButton: View {
    let expanded: Bool
    let onToggle: () -> Void

    // 位置持久化（相对屏幕的 x/y，屏幕坐标系 GeometryReader 内）
    @AppStorage("fabPosX") private var storedX: Double = -1   // -1 = 未初始化，用默认右下
    @AppStorage("fabPosY") private var storedY: Double = -1

    @State private var pos: CGPoint = .zero
    @State private var initialized = false
    @State private var docked: Bool = false   // 是否已吸边隐藏（只露耳朵）

    private let buttonSize: CGFloat = 52
    private let revealWidth: CGFloat = 6      // 吸边后露出的小耳朵宽度
    private let edgeMargin: CGFloat = 8       // 吸边后距屏幕边缘

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                if expanded {
                    // 展开时铺透明点击层：点菜单外任意处 = 收起并重新吸边
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { collapseAndDock() }
                }

                // 展开时菜单贴边显示（左吸边→菜单列也贴左，右同理），收起时在钮位置
                Group {
                    if expanded {
                        // 菜单列：主钮在底部，四个子钮向上展开，整列贴边
                        VStack(spacing: 12) {
                            MenuButtonItem(icon: "house", label: "主页", tint: .clear, size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionHome, object: nil) }
                            MenuButtonItem(icon: "square.split.2x1", label: "分屏", tint: .clear, size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionSplit, object: nil) }
                            MenuButtonItem(icon: "arrow.clockwise", label: "清缓存", tint: .clear, size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionClearCache, object: nil) }
                            MenuButtonItem(icon: "slider.horizontal.3", label: "设置", tint: .clear, size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionSettings, object: nil) }
                            mainButton
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        mainButton
                    }
                }
                .position(expanded ? expandedMenuPosition(size) : (docked ? dockedPosition(size) : clamped(pos, size)))
            }
            .animation(.spring(duration: 0.3), value: docked)
            .animation(.spring(duration: 0.3), value: expanded)
            .onAppear {
                if !initialized {
                    initialized = true
                    if storedX < 0 {
                        // 默认右下
                        pos = CGPoint(x: size.width - 20 - buttonSize/2 - 20, y: size.height - 34 - buttonSize/2 - 20)
                    } else {
                        pos = CGPoint(x: storedX, y: storedY)
                    }
                    docked = storedX > 0 && isNearEdge(pos.x, size.width)
                }
            }
            .onChange(of: size) { newSize in
                pos = clamped(pos, newSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 展开时菜单位置：主钮仍在原地，整列从主钮位置向上展开，且 x 贴到所属侧边
    private func expandedMenuPosition(_ size: CGSize) -> CGPoint {
        let leftSide = pos.x < size.width / 2
        let menuHeight = buttonSize * 5 + 12 * 4   // 5 个钮 + 间距
        let x = leftSide
            ? edgeMargin + buttonSize/2
            : size.width - edgeMargin - buttonSize/2
        // 主钮贴底展开：整列底部 = 主钮位置，向上顶到安全区
        let bottomY = max(pos.y, size.height - 40)
        let y = max(menuHeight/2 + 20, bottomY - (menuHeight/2 - buttonSize/2))
        return CGPoint(x: x, y: y)
    }

    // MARK: 主钮

    private var mainButton: some View {
        Button {
            if docked {
                // 吸边状态轻点：先弹出一点再展开菜单
                withAnimation(.spring(duration: 0.3)) { docked = false }
                onToggle()
            } else if expanded {
                // 展开状态点主钮（×）= 收起并重新吸边
                collapseAndDock()
            } else {
                onToggle()
            }
        } label: {
            Image(systemName: expanded ? "xmark" : "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
        }
        .launcherGlass(.clear, in: .circle, interactive: true)
        // 拖动手势：DragGesture 挂在按钮外层（玻璃按钮点击不冲突）
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    if expanded { return }  // 菜单展开时不拖
                    pos.x += v.translation.width / 8
                    pos.y += v.translation.height / 8
                }
                .onEnded { v in
                    if expanded { return }
                    withAnimation(.spring(duration: 0.3)) {
                        // 判断拖到了左右哪一侧 → 吸边隐藏
                        let screenWidth = UIScreen.main.bounds.width
                        let currentX = pos.x
                        if currentX < screenWidth / 2 {
                            docked = true
                        } else if currentX > screenWidth * 0.45 {
                            docked = true
                        }
                        savePos()
                    }
                }
        )
    }

    // MARK: 吸边坐标

    private func dockedPosition(_ size: CGSize) -> CGPoint {
        let leftSide = pos.x < size.width / 2
        let x = leftSide
            ? edgeMargin + revealWidth - buttonSize/2 + 20   // 只露一点耳朵
            : size.width - edgeMargin - revealWidth + buttonSize/2 - 20
        let y = max(buttonSize/2 + 60, min(size.height - buttonSize/2 - 60, pos.y))
        return CGPoint(x: x, y: y)
    }

    private func isNearEdge(_ x: Double, _ width: Double) -> Bool {
        x < width * 0.15 || x > width * 0.85
    }

    private func clamped(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: max(buttonSize/2, min(size.width - buttonSize/2, p.x)),
                y: max(buttonSize/2 + 40, min(size.height - buttonSize/2 - 20, p.y)))
    }

    private func savePos() {
        storedX = pos.x
        storedY = pos.y
    }

    /// 收起菜单并重新吸边隐藏（点×/点外部时调用）
    private func collapseAndDock() {
        onToggle()  // expanded = false（父视图 withAnimation）
        withAnimation(.spring(duration: 0.3)) { docked = true }
    }
}

// MARK: 菜单子项

struct MenuButtonItem: View {
    let icon: String
    let label: String
    let tint: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
        }
        .launcherGlass(.tinted(tint), in: .circle, interactive: true)
    }
}

// MARK: 悬浮钮动作通知（解耦 FloatingMenuButton 与具体页面）

extension Notification.Name {
    static let fabActionHome = Notification.Name("fabActionHome")
    static let fabActionSplit = Notification.Name("fabActionSplit")
    static let fabActionClearCache = Notification.Name("fabActionClearCache")
    static let fabActionSettings = Notification.Name("fabActionSettings")
}
