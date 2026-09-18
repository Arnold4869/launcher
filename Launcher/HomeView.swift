import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    // 本地 AppStorage：设置页改动实时刷新网格
    @AppStorage("gridColumns") private var gridColumnsCount = 2
    @AppStorage("cardHeight") private var cardHeight: Double = 100
    @AppStorage("cardFontScale") private var fontScale: Double = 1.0
    // 当前主页背景：用于决定文字配色（深色背景要白字）
    @AppStorage("homeBackground") private var bgThemeID = HomeBackgroundImage.defaultThemeID
    @State private var editing: Bookmark?
    @State private var showAdd = false
    @State private var showSplitPicker = false
    @State private var splitTop: Bookmark?
    @State private var splitTopPage: PageState?

    var body: some View {
        NavigationStack {
            // 【自定义背景】背景垫在 NavigationStack 内容之下（ZStack 底层）：
            // 这样空态/加载中/滚动时背景都常驻，且不被 ScrollView 拉扯
            ZStack {
                HomeBackgroundLayer()
                Group {
                    if store.bookmarks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark.slash")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("还没有书签")
                                .foregroundStyle(.secondary)
                            Text("点下方 + 卡片添加第一个")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(store.bookmarks) { bm in
                                    Button {
                                        wm.open(bm)
                                    } label: {
                                        BookmarkCard(bm: bm, cardHeight: CGFloat(cardHeight), fontScale: CGFloat(fontScale))
                                    }
                                    .contextMenu {
                                        Button {
                                            editing = bm
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        Button {
                                            splitTop = bm
                                            splitTopPage = wm.pages.first { $0.bookmark.id == bm.id }
                                            showSplitPicker = true
                                        } label: {
                                            Label("分屏打开", systemImage: "rectangle.split.2x1")
                                        }
                                        Button(role: .destructive) {
                                            store.bookmarks.removeAll { $0.id == bm.id }
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                                // 末尾大加号卡片：跟书签同尺寸，一眼知道是添加
                                AddBookmarkCard(cardHeight: CGFloat(cardHeight)) {
                                    showAdd = true
                                }
                            }
                            .padding()
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    // 主页底部浮动导航栏（常驻，含多任务/新增/更多二级菜单）
                    PageBottomBar(mode: .home)
                        .environmentObject(wm)
                        .environmentObject(store)
                }
                // 【文字可读性】背景是深色（深夜主题/自定义照片）→ 整个主页子树切到 dark colorScheme：
                // .primary 变白、Material 变深磨砂、底栏玻璃/导航栏文字全自动适配，不用逐个改色
                // 浅色背景 → 强制 light（系统深色模式下也不让黑背景压黑字）
                .environment(\.colorScheme, HomeTheme.textStyle(forThemeID: bgThemeID).colorScheme)
            }
            // 导航栏文字跟随背景明暗（.environment(\.colorScheme) 只作用于内容区，工具栏要单独指定）
            .toolbarColorScheme(HomeTheme.textStyle(forThemeID: bgThemeID).colorScheme, for: .navigationBar)
            .navigationTitle("Launcher")
            .sheet(isPresented: $showAdd) {
                BookmarkEditView(store: store, bookmark: nil)
            }
            .sheet(item: $editing) { bm in
                BookmarkEditView(store: store, bookmark: bm)
            }
            .sheet(isPresented: $showSplitPicker) {
                if let top = splitTop {
                    SplitPickerView(top: top, topPage: splitTopPage)
                        .environmentObject(store)
                        .environmentObject(wm)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: gridColumnsCount)
    }
}

struct BookmarkCard: View {
    let bm: Bookmark
    var cardHeight: CGFloat = 100
    var fontScale: CGFloat = 1.0   // 字体缩放，设置页可调
    /// 呈现样式：glass = 主页玻璃浮岛（2.6.0）；solid = 品牌色实底（分屏选择器等浅色 sheet 上用，
    /// 避免玻璃叠在系统浅色背景上几乎看不见）
    var variant: Variant = .glass

    /// 观察使用时长变化信号：主页卡片进度线要随计时实时走（2.6.3）。
    /// 只观察 tracker（不直接读它的 @Published 之外的东西），实际数值仍走 UsageBadgeCache 查询。
    @ObservedObject private var usageTracker = UsageTracker.shared

    enum Variant { case glass, solid }

    /// 按 colorMode 解析品牌色（0随机 / 1图标取色 / 2自定义取色，走缓存）
    static func resolveColors(_ bm: Bookmark) -> [Color] {
        CardPalette.resolvedGradient(for: bm)
    }

    /// 品牌主色：渐变顶色做代表色（圆点/进度线/实底卡共用）
    private var brandColor: Color {
        let g = Self.resolveColors(bm)
        return g.first ?? .accentColor
    }

    /// 限时进度 + 锁定态；未启用限额返回 (nil, false)（走 UsageBadgeCache，滚动不掉帧）
    /// 显式 Optional(...) 构造：避免「无标签元组 + 元素隐式提升为可选」的推断歧义
    private var limitState: (progress: Double?, locked: Bool) {
        guard let s = UsageBadgeCache.shared.progressWithLock(bm) else {
            return (nil, false)
        }
        return (progress: Optional(s.progress), locked: s.locked)
    }

    var body: some View {
        Group {
            switch variant {
            case .glass: glassBody
            case .solid: solidBody
            }
        }
        .frame(height: cardHeight)
    }

    // MARK: 玻璃浮岛（主页）

    private var glassBody: some View {
        // 一次查询同时拿到进度与锁定态（别分开调两次缓存）
        let st = limitState
        // 显式消费刷新信号：usageRevision 变化触发本卡重渲染，进度线随计时实时走（2.6.3）
        let _ = usageTracker.usageRevision
        // 低高度档（滑杆最小 60pt）自适应压缩：
        // 60pt - 上下各 12pt内边距 = 36pt 可用，装不下「圆点行 13pt + 两行字 ~29pt」；
        // 堆叠外层有 frame(height:) 裁剪，直接压字会糊 → 按高度收内边距并给标题留足余量
        // 阈值 96：84pt 档非紧凑时可用 33pt < 两行标题 40pt 会溢出，96 以下全部走紧凑档
        let compact = cardHeight < 96
        let vPad: CGFloat = compact ? 8 : 12
        let hPad: CGFloat = compact ? 12 : 14
        // 标题高度上限：不低于单行高度，最多两行（配合 minimumScaleFactor 自动缩字）
        let titleSize = max(12, cardHeight * 0.20 * fontScale)
        let titleMaxH = compact ? titleSize * 1.25 : titleSize * 1.25 * 2

        // 顺序关键：padding → frame(高度) → 玻璃；
        // 玻璃必须落在「已经撑到 cardHeight 的容器」上，否则只包住内容自然高度
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                // 品牌色圆点：原整卡渐变的色彩标识收敛到这一点
                Circle()
                    .fill(brandColor)
                    .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                Spacer(minLength: 0)
                if bm.timeLimitEnabled {
                    Image(systemName: st.locked ? "lock.fill" : "hourglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: compact ? 2 : 4)
            Text(bm.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
                .frame(maxHeight: titleMaxH, alignment: .bottomLeading)
            // 限时进度线：设了限额才显示（已锁 = 整条变中性色）
            if let p = st.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(st.locked ? Color.secondary : brandColor)
                            .frame(width: max(2, geo.size.width * p))
                    }
                }
                .frame(height: 3)
                .padding(.top, compact ? 4 : 7)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        // ⚠️ frame 必须在 launcherGlassCard 之前：
        // .background 的尺寸取决于「挂载时那个视图的尺寸」，若先挂背景再 frame，
        // 玻璃只会包住内容自然高度（卡片看起来「玻璃没铺满/缩成一条」）
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        // 【玻璃卡】内容卡玻璃：ultraThinMaterial + 品牌色淡 tint（见 GlassSupport.launcherGlassCard 注释，
        // 不走原生 glassEffect：内容卡规范禁止 + 网格性能 + 观感跨版本一致）
        .launcherGlassCard(tint: brandColor)
    }

    // MARK: 实底卡（浅色 sheet 场景，保持旧观感）

    private var solidBody: some View {
        let colors = Self.resolveColors(bm)
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            Text(bm.name)
                .font(.system(size: max(12, cardHeight * 0.20 * fontScale), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
        }
        // 与 glassBody 同样先撑满：分屏选择器网格的 cell 是自适应尺寸，不撑满会缩
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
    }
}

/// 添加书签卡片：跟书签同尺寸的虚线框 + 大加号，一眼知道是「新建」
/// 2.6.0：跟书签卡同款玻璃语言（虚线边框压在照片背景上也要看得清，用 .primary 而非 .secondary）
struct AddBookmarkCard: View {
    var cardHeight: CGFloat = 100
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: max(22, cardHeight * 0.26), weight: .light))
                Text("添加")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.primary.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 同款玻璃底 + 虚线描边（玻璃底保证任意背景上都能看清加号）
            .launcherGlassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(Color.primary.opacity(0.28))
            )
        }
        .buttonStyle(.plain)
        .frame(height: cardHeight)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gridColumns") private var cols = 2
    @AppStorage("cardHeight") private var cardHeight: Double = 100
    @AppStorage("cardFontScale") private var fontScale: Double = 1.0
    // 悬浮按钮开关（彻底隐藏后可在此恢复）
    @AppStorage("fabHidden") private var fabHidden: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("每行显示 \(cols) 个", value: $cols, in: 1...5)
                } header: {
                    Text("列数")
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("卡片高度: \(Int(cardHeight))")
                        Slider(value: $cardHeight, in: 60...200, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("卡片字体大小: \(Int(fontScale * 100))%")
                        Slider(value: $fontScale, in: 0.5...2.0, step: 0.05)
                    }
                } header: {
                    Text("卡片")
                } footer: {
                    Text("书签卡片的高度与字体大小，实时生效")
                }
                // 主页背景：内置渐变 + 相册自定义图（2.6.0）
                HomeBackgroundSettings()
                Section {
                    Toggle("显示悬浮按钮", isOn: Binding(
                        get: { !fabHidden },
                        set: { fabHidden = !$0 }
                    ))
                } header: {
                    Text("悬浮按钮")
                } footer: {
                    Text("关闭后彻底隐藏；打开网页页时可从悬浮按钮菜单里选「隐藏」，在这里恢复")
                }
                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("构建号", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
