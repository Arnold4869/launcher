import SwiftUI

struct BookmarkEditView: View {
    @ObservedObject var store: BookmarkStore
    let bookmark: Bookmark?   // nil = 新建

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var colorIndex: Int = CardPalette.randomIndex()
    @State private var scale: Double = 1.0
    @State private var fontAdjust: Double = 0
    @State private var desktopUA: Bool = false
    @State private var authUser: String = ""
    @State private var authPass: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    // 卡片颜色预览，点击换色
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(colors: CardPalette.colors(for: colorIndex),
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(height: 100)
                        Text(name.isEmpty ? "预览" : name)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    .onTapGesture { colorIndex = CardPalette.randomIndex() }
                    Text("点卡片换颜色")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("名称", text: $name)
                    TextField("网址", text: $urlString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("页面属性") {
                    VStack(alignment: .leading) {
                        Text("页面缩放: \(String(format: "%.1fx", scale))")
                        Slider(value: $scale, in: 0.5...3.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("文字大小: \(fontAdjust >= 0 ? "+" : "")\(Int(fontAdjust))%")
                        Slider(value: $fontAdjust, in: -50...100, step: 5)
                    }
                    Toggle("桌面版页面 (UA)", isOn: $desktopUA)
                }

                Section {
                    TextField("用户名", text: $authUser)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $authPass)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("HTTP Basic Auth (可选)")
                } footer: {
                    Text("填写后自动登录，无需弹窗输密码")
                }
            }
            .navigationTitle(bookmark == nil ? "添加书签" : "编辑书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || urlString.isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let bm = bookmark else { return }
        name = bm.name
        urlString = bm.urlString
        colorIndex = bm.colorIndex
        scale = bm.scale
        fontAdjust = bm.fontAdjust
        desktopUA = bm.desktopUA
        authUser = bm.basicAuthUser
        authPass = bm.basicAuthPass
    }

    private func save() {
        var url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        let bm = Bookmark(
            id: bookmark?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: url,
            icon: bookmark?.icon ?? "🌐",
            colorIndex: colorIndex,
            scale: scale,
            fontAdjust: fontAdjust,
            desktopUA: desktopUA,
            basicAuthUser: authUser,
            basicAuthPass: authPass
        )
        if let idx = store.bookmarks.firstIndex(where: { $0.id == bm.id }) {
            store.bookmarks[idx] = bm
        } else {
            store.bookmarks.append(bm)
        }
        dismiss()
    }
}
