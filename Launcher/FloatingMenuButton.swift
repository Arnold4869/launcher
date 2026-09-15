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
    // 彻底隐藏（设置页可重新启用）
    @AppStorage("fabHidden") private var fabHidden: Bool = false

    @State private var pos: CGPoint = .zero
    @State private var initialized = false
    @State private var docked: Bool = false   // 是否已吸边隐藏（只露耳朵）

    private let buttonSize: CGFloat = 52
    private let revealWidth: CGFloat = 14     // 吸边后露出的耳朵宽度（可点但不突兀）
    private let edgeMargin: CGFloat = 2       // 吸边后距屏幕边缘

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            if fabHidden {
                // 彻底隐藏：设置页「悬浮按钮」开关可恢复
                Color.clear
            } else {
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
                            // 菜单列：主钮在底部，子钮向上展开，整列贴边
                            VStack(spacing: 12) {
                                MenuButtonItem(icon: "house", label: "主页", size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionHome, object: nil) }
                                MenuButtonItem(icon: "chevron.up", label: "工具栏", size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .launcherPageTapped, object: nil) }
                                MenuButtonItem(icon: "square.split.2x1", label: "分屏", size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionSplit, object: nil) }
                                MenuButtonItem(icon: "arrow.clockwise", label: "清缓存", size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionClearCache, object: nil) }
                                MenuButtonItem(icon: "slider.horizontal.3", label: "设置", size: buttonSize) { onToggle(); NotificationCenter.default.post(name: .fabActionSettings, object: nil) }
                                MenuButtonItem(icon: "eye.slash", label: "隐藏", size: buttonSize) {
                                    onToggle()
                                    withAnimation(.spring(duration: 0.3)) { fabHidden = true }
                                }
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
                            // 默认右下角内缩一点（距边 20+20pt，保证拇指能按到）
                            pos = CGPoint(x: size.width - 40, y: size.height - 70)
                        } else {
                            pos = CGPoint(x: storedX, y: storedY)
                        }
                        // 打开书签时自动吸边：位置靠近左右边缘就吸附，不在边缘就保持原位
                        autoDockIfNeeded(size)
                    }
                }
                .onChange(of: size) { newSize in
                    pos = clamped(pos, newSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 展开时菜单位置：整列贴到所属侧边，主钮在列底部（屏幕右/左下角区域向上展开）
    private func expandedMenuPosition(_ size: CGSize) -> CGPoint {
        let leftSide = pos.x < size.width / 2
        // 7 个钮（主页/工具栏/分屏/清缓存/设置/隐藏 + 主钮）+ 间距
        let menuHeight = buttonSize * 7 + 12 * 6
        let x = leftSide
            ? edgeMargin + 18 + buttonSize/2
            : size.width - edgeMargin - 18 - buttonSize/2
        // 列底部贴屏幕底部安全区上方，向上展开
        let y = size.height - 60 - menuHeight/2 + buttonSize/2
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
                .foregroundStyle(.primary)
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
                        // 松手一律吸边：拖到屏幕哪半边就吸哪侧（用完即收，符合"不用时贴边"）
                        docked = true
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

    /// 打开书签时自动吸边：若钮位置接近边缘，直接吸附
    private func autoDockIfNeeded(_ size: CGSize) {
        if isNearEdge(pos.x, size.width) {
            withAnimation(.spring(duration: 0.3)) { docked = true }
        }
    }
}

// MARK: 菜单子项

struct MenuButtonItem: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .semibold))
            }
            // 玻璃透明无色，白字看不清 → 系统主文字色（浅底黑字/深底白字自动适配）
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
        }
        .launcherGlass(.clear, in: .circle, interactive: true)
    }
}

// MARK: 悬浮钮动作通知（解耦 FloatingMenuButton 与具体页面）

extension Notification.Name {
    static let fabActionHome = Notification.Name("fabActionHome")
    static let fabActionTasks = Notification.Name("fabActionTasks")
    static let fabActionSplit = Notification.Name("fabActionSplit")
    static let fabActionClearCache = Notification.Name("fabActionClearCache")
    static let fabActionSettings = Notification.Name("fabActionSettings")
}
