import SwiftUI

struct HomeView: View {
    @StateObject private var store = BookmarkStore()
    @State private var editing: Bookmark?
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 16)
    ]

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
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.bookmarks) { bm in
                                NavigationLink(value: bm) {
                                    BookmarkCard(bm: bm)
                                }
                                .contextMenu {
                                    Button {
                                        editing = bm
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
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
            .navigationDestination(for: Bookmark.self) { bm in
                WebViewScreen(bookmark: bm)
            }
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
}

struct BookmarkCard: View {
    let bm: Bookmark

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemGray6))
                    .frame(width: 64, height: 64)
                Text(bm.icon)
                    .font(.system(size: 32))
            }
            Text(bm.name)
                .font(.footnote)
                .lineLimit(1)
                .frame(width: 96)
        }
        .foregroundStyle(.primary)
    }
}
