import UIKit
import SwiftUI

// MARK: - 网页图标取色（书签卡片背景自动匹配站点品牌色）
//
// 流程：URL host → favicon（Google s2 服务优先，失败直连 /favicon.ico）
//       → 16×16 采样跳过透明像素取主色 → 生成同色相渐变（顶亮底暗）

enum FaviconColor {

    /// 从网页图标提取主色，回调 hex 字符串（RRGGBB，失败返回 nil）
    static func fetchColorHex(for urlString: String, completion: @escaping (String?) -> Void) {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else {
            completion(nil)
            return
        }
        let candidates: [URL] = [
            URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")!,
            URL(string: "https://\(host)/favicon.ico")!,
            URL(string: "https://\(host)/apple-touch-icon.png")!
        ]
        fetch(candidates, index: 0, completion: completion)
    }

    private static func fetch(_ urls: [URL], index: Int, completion: @escaping (String?) -> Void) {
        guard index < urls.count else { completion(nil); return }
        var req = URLRequest(url: urls[index])
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let data = data, let img = UIImage(data: data) {
                if let color = dominantColor(of: img) {
                    completion(color.hexString())
                    return
                }
            }
            fetch(urls, index: index + 1, completion: completion)
        }.resume()
    }

    /// 16×16 采样取主色。
    /// 关键：跳过透明 + 白底 + 灰像素，只保留"有色彩"的像素取平均（否则白底把彩色 logo 平均成灰白）。
    /// 若图标是单色（纯黑/纯色 logo on 白底），退回到"非白非透明"像素平均。
    static func dominantColor(of image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let w = 16, h = 16
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        func isWhiteOrGray(_ r: Int, _ g: Int, _ b: Int) -> Bool {
            let mx = max(r, g, b), mn = min(r, g, b)
            return (mx - mn) < 24 && mx > 210          // 接近白或接近灰
        }
        func isTransparent(_ a: Int) -> Bool { a < 128 }

        // 第一遍：彩色像素（饱和，非白非灰非透明）
        var cr = 0.0, cg2 = 0.0, cb = 0.0, cc = 0.0
        // 第二遍兜底：非白非透明（单色 logo）
        var fr = 0.0, fg2 = 0.0, fb = 0.0, fc = 0.0
        for i in 0..<(w * h) {
            let o = i * 4
            let r = Int(ptr[o + 0]), g = Int(ptr[o + 1]), b = Int(ptr[o + 2]), a = Int(ptr[o + 3])
            if isTransparent(a) { continue }
            if isWhiteOrGray(r, g, b) { continue }
            cr += Double(r); cg2 += Double(g); cb += Double(b); cc += 1
        }
        if cc >= 2 {
            return UIColor(red: cr / cc / 255, green: cg2 / cc / 255, blue: cb / cc / 255, alpha: 1)
        }
        // 兜底：没有足够彩色像素，用非白非透明像素（处理黑白单色图标）
        for i in 0..<(w * h) {
            let o = i * 4
            let r = Int(ptr[o + 0]), g = Int(ptr[o + 1]), b = Int(ptr[o + 2]), a = Int(ptr[o + 3])
            if isTransparent(a) { continue }
            let mx = max(r, g, b)
            if mx < 225 {   // 排除近白像素
                fr += Double(r); fg2 += Double(g); fb += Double(b); fc += 1
            }
        }
        guard fc > 0 else { return nil }
        return UIColor(red: fr / fc / 255, green: fg2 / fc / 255, blue: fb / fc / 255, alpha: 1)
    }
}

// MARK: - 颜色工具

#if canImport(SwiftUI)
import SwiftUI
extension UIColor {
    /// SwiftUI Color → UIColor（ColorPicker 回调用）
    convenience init(_ color: Color) {
        self.init(cgColor: color.cgColor ?? UIColor.clear.cgColor)
    }
}
#endif

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

extension Color {
    init(hex: String) {
        if let c = UIColor(hex: hex) {
            self = Color(uiColor: c)
        } else {
            self = .gray
        }
    }
}
