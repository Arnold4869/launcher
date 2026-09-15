import SwiftUI
import UIKit
import PhotosUI

// MARK: - 主页背景主题层（2.6.0 玻璃浮岛重构）
//
// 设计：书签卡片是浮在背景上的半透明玻璃岛（老板拍板的方案 G）。
// 背景两种来源：
//   1. 内置渐变（HomeTheme.builtins，按 id 存 @AppStorage）
//   2. 相册自定义图片（降采样后存 Documents，AppStorage 只存 "custom" 标记）
// 背景只作用于主页（HomeView），页面层/分屏不受影响。

// MARK: 内置渐变主题

/// 背景明暗 → 文字配色（2.6.0）
/// 深色背景（深夜主题 / 自定义照片）上必须用白字，浅色背景用深色字，
/// 否则「黑字压深蓝」「白字压浅粉」都会看不清（老板要求：保文字图标可读性）
///
/// 实现方式：HomeView 据此覆盖子树的 `\.colorScheme`。
/// 这样 `.primary` / `.secondary` / `Material` 全部自动跟着切换
/// （深色下 .ultraThinMaterial 变深色磨砂 + 白字，玻璃观感一致），
/// 不用给每个文字单独写两套颜色。
enum HomeTextStyle {
    case onLight   // 浅色背景 → 深色文字
    case onDark    // 深色背景 → 白色文字

    var colorScheme: ColorScheme {
        self == .onDark ? .dark : .light
    }
}

struct HomeTheme: Identifiable {
    let id: String
    let name: String
    /// 是否深色背景（决定文字配色与 colorScheme）
    let isDark: Bool
    /// 多层径向渐变 + 底色，模拟 sketch 方案 G 的柔和多彩背景
    let layers: [(center: UnitPoint, radius: CGFloat, color: Color)]
    let base: [Color]   // 线性底色（top->bottom）

    static let builtins: [HomeTheme] = [
        // 暖调（默认）：蜜桃/樱粉/雾蓝/淡紫，同 sketch 007
        HomeTheme(id: "warm", name: "暖调", isDark: false,
                  layers: [(UnitPoint(x: 0.2, y: 0.08), 0.9, Color(red: 1.0, green: 0.85, blue: 0.63)),
                           (UnitPoint(x: 0.88, y: 0.22), 0.85, Color(red: 1.0, green: 0.70, blue: 0.78)),
                           (UnitPoint(x: 0.30, y: 0.68), 0.9, Color(red: 0.62, green: 0.78, blue: 1.0)),
                           (UnitPoint(x: 0.85, y: 0.92), 0.85, Color(red: 0.72, green: 0.64, blue: 1.0))],
                  base: [Color(red: 0.97, green: 0.95, blue: 0.92), Color(red: 0.93, green: 0.91, blue: 0.95)]),
        // 薄荷：浅绿/浅蓝
        HomeTheme(id: "mint", name: "薄荷", isDark: false,
                  layers: [(UnitPoint(x: 0.25, y: 0.10), 0.9, Color(red: 0.80, green: 0.97, blue: 0.88)),
                           (UnitPoint(x: 0.85, y: 0.80), 0.85, Color(red: 0.62, green: 0.88, blue: 0.94))],
                  base: [Color(red: 0.95, green: 0.98, blue: 0.96), Color(red: 0.90, green: 0.96, blue: 0.98)]),
        // 暮色：橙紫黄昏
        HomeTheme(id: "dusk", name: "暮色", isDark: false,
                  layers: [(UnitPoint(x: 0.2, y: 0.05), 0.9, Color(red: 1.0, green: 0.72, blue: 0.45)),
                           (UnitPoint(x: 0.9, y: 0.35), 0.85, Color(red: 0.95, green: 0.50, blue: 0.55)),
                           (UnitPoint(x: 0.4, y: 0.95), 0.9, Color(red: 0.45, green: 0.35, blue: 0.60))],
                  base: [Color(red: 0.98, green: 0.87, blue: 0.80), Color(red: 0.72, green: 0.60, blue: 0.78)]),
        // 深夜：深蓝底 + 幽蓝/紫光（深色 → 白字）
        HomeTheme(id: "night", name: "深夜", isDark: true,
                  layers: [(UnitPoint(x: 0.2, y: 0.10), 0.9, Color(red: 0.18, green: 0.29, blue: 0.54)),
                           (UnitPoint(x: 0.88, y: 0.25), 0.85, Color(red: 0.42, green: 0.25, blue: 0.49))],
                  base: [Color(red: 0.09, green: 0.12, blue: 0.20), Color(red: 0.05, green: 0.07, blue: 0.13)]),
    ]

    static func byID(_ id: String) -> HomeTheme? {
        builtins.first { $0.id == id }
    }

    /// 当前背景应使用的文字配色。
    /// 自定义照片一律按深色处理：统一压暗垫层 + 白字（照片明暗不可控，宁可牺牲一点亮度也不出读不清）
    ///
    /// ⚠️ 例外：选了"custom"但图实际不存在（被系统清理/首次安装）时，背景层会退回默认浅色渐变，
    /// 此时必须按浅色背景处理，否则会出现「白字压浅底」完全看不清。
    /// 用 load() 判断（命中内存缓存，不是每帧读盘）。
    static func textStyle(forThemeID id: String) -> HomeTextStyle {
        if id == "custom" {
            return HomeBackgroundImage.load() != nil ? .onDark : .onLight
        }
        return (byID(id)?.isDark ?? false) ? .onDark : .onLight
    }

    @ViewBuilder
    var view: some View {
        // 半径基准用「较短边」（iPhone 竖屏 = 宽度 r≈351 @390pt）。
        // ⚠️ 不能用较长边：竖屏下会得到 ~726pt 半径，颜色被摊薄到屏幕中点就没了，
        // 背景发灰发白，与定稿的 sketch 方案 G（CSS 百分比径向渐变，rx=90% 宽）观感不符。
        // 也不写死 600pt：小屏/iPad/横屏都不自适应。
        GeometryReader { geo in
            let m = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: base, startPoint: .top, endPoint: .bottom)
                ForEach(0..<layers.count, id: \.self) { i in
                    RadialGradient(colors: [layers[i].color, .clear],
                                   center: layers[i].center,
                                   startRadius: 0,
                                   endRadius: layers[i].radius * m)
                }
            }
        }
    }
}

// MARK: 自定义背景图片（存取 + 缓存）

enum HomeBackgroundImage {
    static let defaultThemeID = "warm"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("launcher-home-bg.jpg")
    }

    // 内存缓存：body 每帧都可能问，磁盘读只做一次
    private static var cachedImage: UIImage?
    /// 是否已尝试过读盘。
    /// 没有这个标志时，「图不存在/被系统清理」会退化成**每帧一次磁盘 I/O**
    /// （load() 从 body 调用，滚动时每帧都跑 → 掉帧）。只在第一次失败后记住结果。
    private static var didAttemptLoad = false
    private static let lock = NSLock()

    /// 取自定义背景（无则 nil）
    static func load() -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let img = cachedImage { return img }
        if didAttemptLoad { return nil }
        didAttemptLoad = true
        guard let data = try? Data(contentsOf: fileURL),
              let img = UIImage(data: data) else { return nil }
        cachedImage = img
        return img
    }

    /// 保存相册选中的图片：最长边压到 1600px、JPEG 0.85，控制内存与磁盘
    /// ⚠️ 缩放是重活（照片可能 12MP+，主线程做会卡顿几百毫秒）→ 后台队列执行
    /// - Parameter completion: 写入与缓存完成后回到主线程调用（调用方据此刷新背景层）
    static func save(from image: UIImage, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let maxSide: CGFloat = 1600
            let size = image.size
            var out = image
            if max(size.width, size.height) > maxSide {
                let scale = maxSide / max(size.width, size.height)
                let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                out = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }
            guard let data = out.jpegData(compressionQuality: 0.85) else {
                DispatchQueue.main.async { completion?() }
                return
            }
            try? data.write(to: fileURL, options: .atomic)
            lock.lock()
            cachedImage = out
            lock.unlock()
            // 必须等文件写 + 缓存更新完再刷新，否则背景层会读到旧图/空图
            DispatchQueue.main.async { completion?() }
        }
    }

    /// 删除自定义背景
    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        lock.lock()
        cachedImage = nil
        didAttemptLoad = false   // 允许下次选图后重新从盘上加载
        lock.unlock()
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// MARK: 背景层视图（HomeView 底层唯一入口）

struct HomeBackgroundLayer: View {
    // 当前背景：builtin id 或 "custom"
    @AppStorage("homeBackground") private var themeID = HomeBackgroundImage.defaultThemeID
    // 自定义图片换新时 bump 一下强制刷新（时间戳）
    @AppStorage("homeBackgroundStamp") private var stamp = 0

    var body: some View {
        ZStack {
            if themeID == "custom" {
                if let img = HomeBackgroundImage.load() {
                    GeometryReader { geo in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .id(stamp) // 换图后强制重建，避免旧缓存图残留
                    // 轻压暗垫层：任意照片上保 .primary 文字对比度（卡片本身还有玻璃模糊兜底）
                    Color.black.opacity(0.12)
                } else {
                    // 图丢了（被系统清理等）退回默认渐变，不留白屏。
                    // 此时 textStyle(forThemeID:) 也会因 load()==nil 走浅色文字，两处判定必须一致
                    (HomeTheme.byID(HomeBackgroundImage.defaultThemeID) ?? HomeTheme.builtins[0]).view
                }
            } else {
                (HomeTheme.byID(themeID) ?? HomeTheme.builtins[0]).view
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: 设置页「主页背景」Section

struct HomeBackgroundSettings: View {
    @AppStorage("homeBackground") private var themeID = HomeBackgroundImage.defaultThemeID
    @AppStorage("homeBackgroundStamp") private var stamp = 0
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Section {
            // 内置渐变：色板横排点选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(HomeTheme.builtins) { theme in
                        Button {
                            themeID = theme.id
                        } label: {
                            VStack(spacing: 5) {
                                // 色板预览：同一个 view 在 56pt 里渲染 = 同一套公式的等比miniature
                                // （半径按容器短边算，所以缩到 56pt 会自动等比缩小，与真机背景构图一致）
                                theme.view
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(themeID == theme.id ? Color.accentColor : Color.clear,
                                                          lineWidth: 2.5)
                                    )
                                Text(theme.name)
                                    .font(.caption2)
                                    .foregroundStyle(themeID == theme.id ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("主页背景")
        } footer: {
            Text("书签卡片浮在此背景上；选自定义图片时会轻微压暗以保证文字可读")
        }

        Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("从相册选择背景图", systemImage: "photo.on.rectangle")
            }
            if themeID == "custom" && HomeBackgroundImage.exists() {
                Button(role: .destructive) {
                    HomeBackgroundImage.remove()
                    themeID = HomeBackgroundImage.defaultThemeID
                } label: {
                    Label("移除自定义背景", systemImage: "trash")
                }
            }
        } header: {
            Text("自定义图片")
        } footer: {
            Text("图片仅保存在本机 App 内，最长边压缩到 1600px")
        }
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    // 保存是异步的；等写入+缓存完成再切 "custom" 并 bump stamp，
                    // 保证背景层第一次渲染就能拿到新图
                    HomeBackgroundImage.save(from: img) {
                        themeID = "custom"
                        stamp += 1
                    }
                }
                photoItem = nil
            }
        }
    }
}
