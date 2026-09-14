import Foundation
import WebKit

// MARK: - 页面内查找（「更多」→ 查找页面）
//
// 走 WebKit 非标准但长期存在的 window.find(term, caseSensitive, backwards, wrap, ...)：
// 每次调用把「下一个/上一个」匹配选中并滚动到可见处，正是 Safari 旧版查找的行为。
// 匹配总数 window.find 不返回 → 另跑一段计数脚本（遍历文本节点，封顶 999 防大页面卡死）。
// 万一某个版本没有 window.find（返回 "unsupported"），退化为官方 find(_:configuration:)：
// 全量高亮 + 定位第一个，但无法逐级步进（UI 上如实标注）。

enum PageFind {
    /// 统计匹配数（0 = 无匹配）
    static func count(_ term: String, in webView: WKWebView, done: @escaping (Int) -> Void) {
        let lit = jsLiteral(term)
        let js = """
        (function(){
          try {
            var term = \(lit);
            if (!term) return 0;
            var lt = term.toLowerCase();
            var walker = document.createTreeWalker(document.body || document.documentElement,
                                                   NodeFilter.SHOW_TEXT, null);
            var n = 0, node;
            while ((node = walker.nextNode())) {
              var t = node.nodeValue;
              if (!t) continue;
              var lower = t.toLowerCase(), idx = 0;
              while ((idx = lower.indexOf(lt, idx)) !== -1) {
                n++; idx += lt.length;
                if (n >= 999) return n;
              }
            }
            return n;
          } catch (e) { return 0; }
        })();
        """
        webView.evaluateJavaScript(js) { res, _ in
            done((res as? NSNumber)?.intValue ?? 0)
        }
    }

    /// 步进到下一个/上一个匹配。ok=false + unsupported=true 表示页面不支持 window.find
    static func step(_ term: String, backwards: Bool,
                     in webView: WKWebView,
                     done: @escaping (_ ok: Bool, _ unsupported: Bool) -> Void) {
        let lit = jsLiteral(term)
        let js = """
        (function(){
          try {
            if (typeof window.find !== 'function') return 'unsupported';
            var r = window.find(\(lit), false, \(backwards ? "true" : "false"), true, false, true, false);
            return r ? 'true' : 'false';
          } catch (e) { return 'unsupported'; }
        })();
        """
        webView.evaluateJavaScript(js) { res, _ in
            guard let s = res as? String else { done(false, true); return }
            if s == "unsupported" {
                // 退化：官方 API 全量高亮 + 定位第一个/最后一个
                let cfg = WKFindConfiguration()
                cfg.caseSensitive = false
                cfg.backwards = backwards
                cfg.wraps = true
                webView.find(term, configuration: cfg) { result in
                    done(result.matchFound, true)
                }
            } else {
                done(s == "true", false)
            }
        }
    }

    /// 清掉查找留下的选中高亮
    static func clear(in webView: WKWebView) {
        webView.evaluateJavaScript("try{window.getSelection().removeAllRanges();}catch(e){}",
                                   completionHandler: nil)
    }

    private static func jsLiteral(_ s: String) -> String {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
