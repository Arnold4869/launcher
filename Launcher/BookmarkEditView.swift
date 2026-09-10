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
    @State private var loginUser: String = ""
    @State private var loginPass: String = ""
    @State private var autoSubmit: Bool = true
    @State private var colorMode: Int = 0
    @State private var autoColorHex: String = ""
    @State private var customColorHex: String = ""
    @State private var generatingColor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    // 卡片颜色预览
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(colors: previewColors,
                                                 startPoint: .top,
                                                 endPoint: .bottom))
                            .frame(height: 100)
                        Text(name.isEmpty ? "预览" : name)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    .onTapGesture {
                        if colorMode == 0 { colorIndex = CardPalette.randomIndex() }
                    }

                    // 三种取色方式
                    Picker("取色方式", selection: $colorMode) {
                        Text("随机色").tag(0)
                        Text("网页图标色").tag(1)
                        Text("自定义").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: colorMode) { mode in
                        if mode == 1 && autoColorHex.isEmpty { generateFromFavicon() }
                    }

                    if colorMode == 0 {
                        Button {
                            colorIndex = CardPalette.randomIndex()
                        } label: {
                            Label("换一个随机色", systemImage: "shuffle")
                        }
                    } else if colorMode == 1 {
                        Button {
                            generateFromFavicon()
                        } label: {
                            if generatingColor {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("提取中…")
                                }
                            } else {
                                Label("重新从图标取色", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(generatingColor)
                    } else {
                        // 自定义取色：ColorPicker + 预设色板
                        ColorPicker("选择颜色", selection: Binding(
                            get: { Color(hex: customColorHex.isEmpty ? "3B82F6" : customColorHex) },
                            set: { c in customColorHex = UIColor(c).hexString() }
                        ))
                    }

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

                Section {
                    TextField("用户名", text: $loginUser)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                    SecureField("密码", text: $loginPass)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textContentType(.password)
                } header: {
                    Text("网页登录自动填充 (可选)")
                } footer: {
                    Text("页面检测到登录表单时自动填入；账号可从 Bitwarden 复制粘贴")
                }
                Section {
                    Toggle("填入后自动登录", isOn: $autoSubmit)
                } footer: {
                    Text("开启后自动填充完成即模拟回车/点击登录按钮；关闭则填入后等你手动提交")
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
                        // 【系统原生玻璃】iOS26 toolbar 按钮自动获得 Liquid Glass；<26 系统默认样式
                        .fontWeight(.semibold)
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
        loginUser = bm.loginUser
        loginPass = bm.loginPass
        autoSubmit = bm.autoSubmit
        colorMode = bm.colorMode
        autoColorHex = bm.autoColorHex
        customColorHex = bm.customColorHex
    }

    private var previewColors: [Color] {
        switch colorMode {
        case 1: return CardPalette.gradient(fromHex: autoColorHex) ?? CardPalette.colors(for: colorIndex)
        case 2: return CardPalette.gradient(fromHex: customColorHex) ?? CardPalette.colors(for: colorIndex)
        default: return CardPalette.colors(for: colorIndex)
        }
    }

    private func generateFromFavicon() {
        generatingColor = true
        FaviconColor.fetchColorHex(for: urlString) { hex in
            DispatchQueue.main.async {
                generatingColor = false
                if let hex = hex {
                    autoColorHex = hex
                }
                // 提取失败保持旧色，autoColor 仍开启但用旧渐变兜底
            }
        }
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
            basicAuthPass: authPass,
            loginUser: loginUser,
            loginPass: loginPass,
            autoSubmit: autoSubmit,
            colorMode: colorMode,
            autoColorHex: autoColorHex,
            customColorHex: customColorHex
        )
        if let idx = store.bookmarks.firstIndex(where: { $0.id == bm.id }) {
            store.bookmarks[idx] = bm
        } else {
            store.bookmarks.append(bm)
        }
        dismiss()
    }
}
