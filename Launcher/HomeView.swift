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
                        Text("📭").font(.system(size: 56))
                        Text("还没有书签")
                            .foregroundStyle(.secondary)
                        Text("点右上角 + 添加第一个")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            // 多任务入口卡（有打开页面时显示，像书签 tile 一样点进去切换）
                            if !wm.pages.isEmpty {
                                Button {
                                    showTaskSwitcher = true
                                } label: {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.blue.opacity(0.12))
                                                .frame(height: CGFloat(cardHeight))
                                            Image(systemName: "square.on.square")
                                                .font(.system(size: 30))
                                                .foregroundStyle(.blue)
                                        }
                                        Text("多任务 (\(wm.pages.count))")
                                            .font(.footnote)
                                            .lineLimit(1)
                                    }
                                }
                            }
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
            .navigationTitle("Launcher")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTaskSwitcher = true
                    } label: {
                        // 类浏览器标签页管理入口，角标显示后台页数
                        Image(systemName: "square.on.square.dashed")
                            .overlay(alignment: .topTrailing) {
                                if !wm.pages.isEmpty {
                                    Text("\(wm.pages.count)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Circle().fill(.blue))
                                        .offset(x: 8, y: -6)
                                }
                            }
                    }
                }
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

    var body: some View {
        let colors = CardPalette.colors(for: bm.colorIndex)
        // 深色渐变，白字对比清晰
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: colors,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .brightness(-0.18)
                .frame(height: cardHeight)
                .shadow(color: colors[1].opacity(0.35), radius: 6, x: 0, y: 3)
            Text(bm.name)
                .font(.system(size: max(11, cardHeight * 0.22 * fontScale), weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
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
