import Foundation

/// 一个打开的页面（常驻 WebView，最多 2 个）
final class PageState: Identifiable {
    let id = UUID()
    let bookmark: Bookmark
    init(_ bm: Bookmark) { self.bookmark = bm }
}
