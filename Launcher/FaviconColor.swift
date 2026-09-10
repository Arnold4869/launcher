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

    /// 16×16 采样，跳过透明像素，平均出不透明像素的主色
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
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for i in 0..<(w * h) {
            let o = i * 4
            if Double(ptr[o + 3]) / 255 < 0.5 { continue }   // 跳过透明像素
            r += Double(ptr[o + 0]); g += Double(ptr[o + 1]); b += Double(ptr[o + 2]); count += 1
        }
        guard count > 0 else { return nil }
        return UIColor(red: r / count / 255, green: g / count / 255, blue: b / count / 255, alpha: 1)
    }
}

// MARK: - 颜色工具

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
