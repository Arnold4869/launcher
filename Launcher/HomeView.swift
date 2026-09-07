import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var wm: WindowManager
    // 本地 AppStorage：设置页改动实时刷新网格
    @AppStorage("gridColumns") private var gridColumnsCount = 2
    @AppStorage("cardHeight") private var cardHeight: Double = 100
    @State private var editing: Bookmark?
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showSettings = false
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
                            ForEach(store.bookmarks) { bm in
                                Button {
                                    wm.open(bm)
                                } label: {
                                    BookmarkCard(bm: bm, cardHeight: CGFloat(cardHeight))
                                }
                                .contextMenu {
                                    Button {
                                        editing = bm
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    Button {
                                        splitPair = SplitPair(top: bm, bottom: bm)
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
            .fullScreenCover(item: $splitPair) { pair in
                SplitFlowView(top: pair.top, store: store)
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
    var cardHeight: CGFloat = 100   // 默认从 130 降到 100

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
                .font(.system(size: max(15, cardHeight * 0.22), weight: .bold))
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("每行显示 \(cols) 个", value: $cols, in: 1...5)
                    VStack(alignment: .leading) {
                        Text("卡片高度: \(Int(cardHeight))")
                        Slider(value: $cardHeight, in: 60...200, step: 5)
                    }
                } footer: {
                    Text("一行显示的书签卡片数量与卡片高度")
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
