import SwiftUI

// MARK: - Liquid Glass 兼容层（iOS 26+ 用原生 glassEffect，<26 降级 Material）
//
// 用法约定（全项目唯一玻璃入口，不要直接调原生 .glassEffect）：
//   .launcherGlass(.regular, in: .circle)                    // 普通玻璃容器
//   .launcherGlass(.tinted(.blue), in: .circle, interactive: true)  // 带色玻璃+交互反馈
//   .launcherButtonStyle(.glass) / .launcherButtonStyle(.glassProminent)
//
// 约束遵循（Apple HIG / Liquid Glass 指南）：
// - 玻璃只用于导航层与悬浮控件（工具栏/悬浮钮/Sheet 标题栏），内容卡片/列表/网页本体禁止
// - 不玻璃叠玻璃：glassEffect 不施加在已有玻璃的控件上
// - 降级：iOS <26 用 .ultraThinMaterial + tint 混色模拟，可用性一致

enum LauncherGlassStyle {
    case regular          // 标准：工具栏/导航容器
    case clear            // 高透明：媒体上方的小控件（悬浮钮在网页上=媒体上方，符合 clear 使用条件）
    case tinted(Color)    // 带色玻璃：淡彩透玻璃，语义标识
    case prominent(Color) // 强调按钮（对应 .glassProminent）

    var tintColor: Color? {
        if case .tinted(let c) = self { return c }
        if case .prominent(let c) = self { return c }
        return nil
    }
}

// MARK: - View modifier（容器玻璃）

private struct LauncherGlassModifier<S: Shape>: ViewModifier {
    let style: LauncherGlassStyle
    let shape: S
    let interactive: Bool

    @available(iOS 26.0, *)
    static func nativeGlass(_ style: LauncherGlassStyle, interactive: Bool) -> Glass {
        let base: Glass
        switch style {
        case .regular: base = .regular
        case .clear: base = .clear
        case .tinted: base = .regular
        case .prominent: base = .regular
        }
        var g = base
        if let tint = style.tintColor { g = g.tint(tint.opacity(0.45)) }   // 淡淡色彩透玻璃（约束 5）
        if interactive { g = g.interactive() }                              // 交互控件触摸反馈（约束 3）
        return g
    }

    /// 材质选择（<26 降级用）：clear 变体用更透的 ultraThin
    var legacyMaterial: Material {
        if case .clear = style { return Material.ultraThinMaterial }
        return Material.regularMaterial
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 【系统原生玻璃】iOS 26 真实 Liquid Glass：lens 折射+动态高光
            content.glassEffect(Self.nativeGlass(style, interactive: interactive), in: shape)
        } else {
            // 【自定义玻璃】<26 降级：Material 模拟 + tint overlay
            content
                .background(
                    ZStack {
                        shape.fill(style.legacyMaterial)
                        if let tint = style.tintColor {
                            shape.fill(tint.opacity(0.25)).blendMode(.overlay)
                        }
                    }
                )
                // 降级时补一个轻阴影保持层次（原生玻璃自带立体感，Material 没有）
                .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
        }
    }
}

// MARK: - ButtonStyle（按钮玻璃）

struct LauncherGlassButtonStyle: ButtonStyle {
    enum Variant { case glass, glassProminent }
    let variant: Variant
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            // 【系统原生玻璃】原生 buttonStyle，自动带按压 morph 动画
            if variant == .glassProminent {
                configuration.label.buttonStyle(.glassProminent).tint(tint)
            } else {
                configuration.label.buttonStyle(.glass)
            }
        } else {
            // 【自定义玻璃】降级：Material 圆角胶囊 + 按压变暗
            configuration.label
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
                        if let tint { RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.25)).blendMode(.overlay) }
                    }
                )
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        }
    }
}

// MARK: - 便捷扩展

extension View {
    /// 项目统一玻璃入口。iOS 26+ = 原生 glassEffect；<26 = Material 降级
    func launcherGlass(_ style: LauncherGlassStyle = .regular,
                       in shape: some Shape = .capsule,
                       interactive: Bool = false) -> some View {
        modifier(LauncherGlassModifier(style: style, shape: shape, interactive: interactive))
    }

    /// 按钮玻璃样式：iOS 26+ 用 .glass/.glassProminent，<26 降级
    @ViewBuilder
    func launcherButtonStyle(_ variant: LauncherGlassButtonStyle.Variant, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            // 原生路径直接用系统样式
            if variant == .glassProminent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(LauncherGlassButtonStyle(variant: variant, tint: tint))
        }
    }
}
