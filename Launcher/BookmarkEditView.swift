import SwiftUI

struct BookmarkEditView: View {
    @ObservedObject var store: BookmarkStore
    let bookmark: Bookmark?   // nil = 新建

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var icon: String = "🌐"
    @State private var scale: Double = 1.0
    @State private var fontAdjust: Double = 0
    @State private var desktopUA: Bool = false

    private let iconChoices = ["🌐", "📊", "💼", "🔧", "📺", "🎵", "📚", "⚙️", "🏠", "🚀", "💬", "🛒", "🎮", "📰"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("图标")
                        Spacer()
                        Text(icon).font(.system(size: 28))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(iconChoices, id: \.self) { choice in
                                Text(choice)
                                    .font(.system(size: 26))
                                    .padding(6)
                                    .background(icon == choice ? Color.blue.opacity(0.2) : .clear)
                                    .cornerRadius(8)
                                    .onTapGesture { icon = choice }
                            }
                        }
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
        icon = bm.icon
        scale = bm.scale
        fontAdjust = bm.fontAdjust
        desktopUA = bm.desktopUA
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
            icon: icon,
            scale: scale,
            fontAdjust: fontAdjust,
            desktopUA: desktopUA
        )
        if let idx = store.bookmarks.firstIndex(where: { $0.id == bm.id }) {
            store.bookmarks[idx] = bm
        } else {
            store.bookmarks.append(bm)
        }
        dismiss()
    }
}
