import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    // 本地 AppStorage：设置页改动实时刷新网格
    @AppStorage("gridColumns") private var gridColumnsCount = 2
    @AppStorage("cardHeight") private var cardHeight: Double = 100
    @AppStorage("cardFontScale") private var fontScale: Double = 1.0
    @State private var editing: Bookmark?
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showSettings = false
    @State private var showTaskSwitcher = false
    @State private var splitPair: SplitPair?

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("还没有书签")
                            .foregroundStyle(.secondary)
                        Text("点右上角 + 添加第一个")
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
                                        splitPair = SplitPair(top: bm, topPage: wm.pages.first { $0.bookmark.id == bm.id })
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
            .navigationTitle("Launcher")
            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: store.exportURL(),
                                  preview: SharePreview("launcher-bookmarks.json")) {
                            Label("导出书签", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("导入书签", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                BookmarkEditView(store: store, bookmark: nil)
            }
            .sheet(item: $editing) { bm in
                BookmarkEditView(store: store, bookmark: bm)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showTaskSwitcher) {
                TaskSwitcherView()
                    .environmentObject(store)
                    .environmentObject(wm)
            }
            .fullScreenCover(item: $splitPair) { pair in
                SplitFlowView(top: pair.top, topPage: pair.topPage, store: store)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    let n = store.importFrom(url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    importMessage = n >= 0 ? "成功导入 \(n) 个书签" : "导入失败：文件格式不对"
                    showImportAlert = true
                }
            }
            .alert("导入结果", isPresented: $showImportAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
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

    /// 按 colorMode 解析卡片渐变：0随机 / 1图标取色 / 2自定义取色（走缓存）
    static func resolveColors(_ bm: Bookmark) -> [Color] {
        CardPalette.resolvedGradient(for: bm)
    }

    var body: some View {
        let colors = Self.resolveColors(bm)
        // 同色相渐变 + 中性细阴影（不挂彩色阴影，避免 AI 味）
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: colors,
                                     startPoint: .top,
                                     endPoint: .bottom))
                .frame(height: cardHeight)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            Text(bm.name)
                .font(.system(size: max(12, cardHeight * 0.20 * fontScale), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)

            // 限时/已锁角标：右上角小图标，不抢视觉
            if bm.timeLimitEnabled {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: UsageTracker.shared.isLocked(bm) ? "lock.fill" : "hourglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(5)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cols = GridSettings.columns
    @AppStorage("cardHeight") private var cardHeight: Double = 100
    @AppStorage("cardFontScale") private var fontScale: Double = 1.0
    // 悬浮按钮开关（彻底隐藏后可在此恢复）
    @AppStorage("fabHidden") private var fabHidden: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // 一级菜单：分类入口，收进二级页面
                Section {
                    NavigationLink {
                        BookmarkGridSettingsView(cols: $cols, cardHeight: $cardHeight, fontScale: $fontScale)
                    } label: {
                        Label("主屏布局", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        FabSettingsView(fabHidden: $fabHidden)
                    } label: {
                        Label("悬浮按钮", systemImage: "record.circle")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        GridSettings.columns = cols
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 二级：主屏布局设置
struct BookmarkGridSettingsView: View {
    @Binding var cols: Int
    @Binding var cardHeight: Double
    @Binding var fontScale: Double

    var body: some View {
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
        }
        .navigationTitle("主屏布局")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 二级：悬浮按钮设置
struct FabSettingsView: View {
    @Binding var fabHidden: Bool

    var body: some View {
        Form {
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
        }
        .navigationTitle("悬浮按钮")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 二级：关于
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                LabeledContent("构建号", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
            } header: {
                Text("Launcher")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
