import SwiftUI
import WebKit

// MARK: - 页面工具面板（底栏「更多」→ 底部弹出）
//
// 主流浏览器（Safari ⋯ / Chrome ⋮）都是「底部工具面板」而不是长下拉菜单：条目多、要分组、
// 要展示当前值（网址、访问标识），下拉菜单塞不下也看不清。本面板就是这个角色，只负责
// 当前页相关的事（书签导入导出继续留在最后一段）。
//
// 布局（自上而下）：
//   ① 地址行：当前网址（点击=复制）
//   ② 页面段：查找页面 / 页面缩放 / 访问标识（菜单，显示当前档）
//   ③ 分享段：图片页=分享图片+分享网址；普通页=分享面板（PNG 截图 / 整页 PDF / 分享网址）
//   ④ 书签段：导入 / 导出 / 设置
//
// 「查找页面」「页面缩放」需要宿主页面配合（查找条要挂在网页上层、缩放要写回宿主 @State），
// 所以通过 onFind / onZoom 回调交给宿主，本面板只负责关掉自己再触发（0.35s 防 sheet 竞态）。

struct PageToolsPanel: View {
    let wv: WKWebView
    var onFind: (() -> Void)? = nil
    var onZoom: (() -> Void)? = nil

    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss

    @State private var isImagePage = false
    @State private var copied = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    private var index: Int? { store.bookmarks.firstIndex(where: { $0.id == wv.currentBookmark.id }) }
    private var uaMode: Int { index.map { store.bookmarks[$0].uaMode } ?? 0 }
    private var urlText: String { PageShare.displayURL(wv) }

    var body: some View {
        NavigationStack {
            List {
                // ① 地址行
                Section {
                    Button {
                        PageShare.copyURL(wv)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: urlText.hasPrefix("https") ? "lock.fill" : "globe")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(urlText)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.footnote)
                                .foregroundStyle(copied ? Color.accentColor : .secondary)
                        }
                    }
                } footer: {
                    Text("点击地址复制网址")
                }

                // ② 页面
                Section("页面") {
                    if let onFind {
                        row("查找页面", "magnifyingglass") { closeThen(onFind) }
                    }
                    if let onZoom {
                        row("页面缩放", "textformat.size") { closeThen(onZoom) }
                    }
                    // 访问标识：当前档直接显示在行尾，菜单里打勾
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.footnote)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        Menu {
                            ForEach(0..<UserAgentOption.titles.count, id: \.self) { m in
                                Button {
                                    setUAMode(m)
                                } label: {
                                    if m == uaMode {
                                        Label(UserAgentOption.titles[m], systemImage: "checkmark")
                                    } else {
                                        Text(UserAgentOption.titles[m])
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("访问标识").foregroundStyle(.primary)
                                Spacer()
                                Text(UserAgentOption.shortTitle(for: uaMode))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // ③ 分享
                Section("分享") {
                    if isImagePage {
                        row("分享图片", "photo") { closeThen { PageShare.shareCurrentImage(wv) } }
                        row("分享网址", "link") { closeThen { PageShare.shareURL(wv) } }
                    } else {
                        Menu {
                            Button { closeThen { PageShare.shareVisibleSnapshot(wv) } } label: {
                                Label("当前屏幕 PNG 截图", systemImage: "photo")
                            }
                            Button { closeThen { PageShare.shareFullPDF(wv) } } label: {
                                Label("整页 PDF", systemImage: "doc.richtext")
                            }
                            Button { closeThen { PageShare.shareURL(wv) } } label: {
                                Label("只分享网址", systemImage: "link")
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.footnote)
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)
                                Text("分享页面").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // ④ 书签
                Section("书签") {
                    row("导入书签", "square.and.arrow.down") { showImporter = true }
                    ShareLink(item: store.exportURL(), preview: SharePreview("launcher-bookmarks.json")) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.doc")
                                .font(.footnote)
                                .frame(width: 22)
                                .foregroundStyle(.secondary)
                            Text("导出书签").foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    row("设置", "gearshape") { showSettings = true }
                }
            }
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                PageShare.isImagePage(wv) { v in isImagePage = v }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
        // 面板本身是工具面板，.medium 高度够用且不遮住整个网页
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 行 / 动作

    private func row(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(title).foregroundStyle(.primary)
                Spacer()
            }
        }
    }

    /// 关掉面板再执行（否则「面板 dismiss」和「宿主开新 sheet」同时发生会互相吃掉）
    private func closeThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    /// 切访问标识：写回书签（持久化）+ 立刻作用到当前 WebView 并重载
    private func setUAMode(_ mode: Int) {
        if let i = index {
            store.bookmarks[i].uaMode = mode
            store.bookmarks[i].desktopUA = (mode == 2)   // legacy 字段同步，导出给旧版也能懂
        }
        wv.applyUAMode(mode)
    }
}
