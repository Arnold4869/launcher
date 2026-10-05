import SwiftUI
import UIKit

// MARK: - 主页书签网格：长按拖动排序（2.7.0）
//
// 为什么不用 LazyVGrid：拖动排序需要每张卡的「槽位坐标」精确可控 + 换位时能平滑滑到新槽位。
// LazyVGrid 只负责布局不给坐标，重排是瞬移。这里改成 GeometryReader 手工排版的 ZStack
// （槽位 = 行×列，算术与原 GridItem(.flexible, spacing:14) 完全一致，观感不变）。
//
// 手势全走 UIKit（沿用 CardInteraction.swift 的结论：SwiftUI 手势挂在滚动视图子视图上会抢滚动
// 且无法主动 fail）。GridDragUIView 一个长按识别器串起：抬起 / 拖动 / 边缘自动滚动，
// 松手时按「有没有真的移动过」决定是落位还是弹菜单。
//
// 换位算法（关键，容易写错）：
// · 拖动卡在屏幕上钉在「起手槽位 + 手指位移」，**不随数组下标变化**（否则每换一格就跳一下）
// · 目标槽位永远由「起手槽位 + 位移」反算
// · 数组只做一件事：把被拖的卡挪到目标下标，其余卡靠 .animation(value: index) 滑过去
// · 拖动期间的顺序只存在控制器里，**松手才一次性提交 store**（每次换位都写 json 是多余的磁盘 IO）

// MARK: - 网格度量

struct GridMetrics {
    var columns: Int
    var cardHeight: CGFloat
    var spacing: CGFloat
    /// 网格可用宽度（已扣掉外层水平 padding）
    var width: CGFloat
    /// 格子总数（书签数 + 末尾「添加」格）
    var cellCount: Int

    /// 书签能占的最大下标：添加格固定在末尾，不参与排序
    var maxBookmarkIndex: Int { max(0, cellCount - 2) }

    var cellWidth: CGFloat {
        guard columns > 0 else { return 0 }
        let gaps = spacing * CGFloat(columns - 1)
        return max(40, (width - gaps) / CGFloat(columns))
    }
    var colStride: CGFloat { cellWidth + spacing }
    var rowStride: CGFloat { cardHeight + spacing }
    var rows: Int {
        guard cellCount > 0, columns > 0 else { return 0 }
        return Int((Double(cellCount) / Double(columns)).rounded(.up))
    }
    var totalHeight: CGFloat { rows <= 0 ? 0 : rowStride * CGFloat(rows) - spacing }

    /// 第 index 格的左上角（相对网格原点）
    func origin(index: Int) -> CGPoint {
        guard columns > 0 else { return .zero }
        let i = max(0, index)
        return CGPoint(x: CGFloat(i % columns) * colStride, y: CGFloat(i / columns) * rowStride)
    }

    /// 「卡左上角相对网格原点的偏移」→ 槽位下标。
    /// 用 round 而非 floor：拖过中线就换位，跟 iOS 主屏的观感一致。
    func index(forOffset offset: CGSize) -> Int {
        guard columns > 0 else { return 0 }
        let col = Int((offset.width / colStride).rounded())
        let row = Int((offset.height / rowStride).rounded())
        let raw = max(0, row) * columns + max(0, col)
        return min(max(0, raw), maxBookmarkIndex)
    }
}

// MARK: - 拖动状态

/// 长按拖动的共享状态。观察者只有网格容器，一屏最多几十张卡，拖动时每帧重算一次可接受。
final class BookmarkGridDragController: ObservableObject {
    /// 正在拖动的书签
    @Published private(set) var draggingID: UUID?
    /// 已长按「抬起」但还没开始移动的书签（等一下：动了 = 拖排序，没动松手 = 弹菜单）
    @Published private(set) var liftedID: UUID?
    /// 拖动位移（内容坐标系：已扣掉本次滚动量，自动滚动时才不脱手）
    @Published private(set) var offset: CGSize = .zero
    /// 拖动期间的临时顺序（nil = 跟随 store）
    @Published private(set) var order: [Bookmark]?
    /// 长按松手位置（窗口坐标）——自绘菜单按它定位；nil = 屏幕中心
    @Published var menuAnchor: CGPoint?

    /// 渲染锚点：起手槽位，全程不变 → 拖动卡不因换位而跳动
    private(set) var anchorIndex: Int = 0
    /// 被拖卡片在 `order` 里的当前下标
    private(set) var currentIndex: Int = 0

    /// 拖动期间生效的顺序
    func displayOrder(_ fallback: [Bookmark]) -> [Bookmark] { order ?? fallback }

    func lift(_ id: UUID) {
        liftedID = id
        offset = .zero
        order = nil
    }

    /// 开始真正拖动（首次越过移动阈值）
    func begin(_ id: UUID, index: Int, list: [Bookmark]) {
        draggingID = id
        liftedID = nil
        anchorIndex = index
        currentIndex = index
        offset = .zero
        order = list
    }

    func move(to newOffset: CGSize) {
        offset = newOffset
    }

    /// 换位：把被拖卡片从 currentIndex 挪到 target
    func swap(to target: Int) {
        guard var list = order, target != currentIndex,
              list.indices.contains(currentIndex), list.indices.contains(target) else { return }
        // move(fromOffsets:toOffset:) 的 toOffset 是「插入位置」：往后挪要 +1 才正好落在 target
        list.move(fromOffsets: IndexSet(integer: currentIndex),
                  toOffset: target > currentIndex ? target + 1 : target)
        order = list
        currentIndex = target
    }

    /// 落位时取最终顺序（松手提交前调用）
    func orderSnapshot() -> [Bookmark]? { order }

    /// 结束手势。返回 true = 发生过拖动（不该弹菜单）
    @discardableResult
    func end() -> Bool {
        let dragged = draggingID != nil
        draggingID = nil
        liftedID = nil
        offset = .zero
        order = nil
        anchorIndex = 0
        currentIndex = 0
        return dragged
    }

    /// 记录长按松手点（弹自绘菜单前调用）
    func setMenuAnchor(_ p: CGPoint) {
        menuAnchor = p
    }
}

// MARK: - 网格

struct BookmarkGrid: View {
    let items: [Bookmark]
    let columns: Int
    let cardHeight: CGFloat
    let fontScale: CGFloat
    @ObservedObject var drag: BookmarkGridDragController
    let onTap: (Bookmark) -> Void
    let onMenu: (Bookmark) -> Void
    let onAdd: () -> Void
    let onReorder: ([Bookmark]) -> Void

    private let spacing: CGFloat = 14

    var body: some View {
        // 拖动期间用临时顺序；松手才落 store
        let list = drag.displayOrder(items)
        return GeometryReader { geo in
            let m = GridMetrics(columns: max(1, columns),
                                cardHeight: cardHeight,
                                spacing: spacing,
                                width: geo.size.width,
                                cellCount: list.count + 1)   // +1 = 末尾添加格
            ZStack(alignment: .topLeading) {
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, bm in
                    card(bm, index: idx, metrics: m, list: list)
                }
                // 末尾添加卡：固定位置，不参与拖动排序
                AddBookmarkCard(cardHeight: cardHeight, onTap: onAdd)
                    .frame(width: m.cellWidth, height: cardHeight)
                    .offset(x: m.origin(index: list.count).x,
                            y: m.origin(index: list.count).y)
            }
            .frame(width: geo.size.width, height: m.totalHeight, alignment: .topLeading)
        }
        .frame(height: estimatedHeight)
    }

    /// GeometryReader 自身不产高度，给死算出来的高度：宽度由它自己量，高度只跟列数/卡片高有关
    private var estimatedHeight: CGFloat {
        let count = drag.displayOrder(items).count + 1
        let rows = Int((Double(count) / Double(max(1, columns))).rounded(.up))
        return rows <= 0 ? 0 : (cardHeight + spacing) * CGFloat(rows) - spacing
    }

    @ViewBuilder
    private func card(_ bm: Bookmark, index: Int, metrics m: GridMetrics, list: [Bookmark]) -> some View {
        let isDragging = drag.draggingID == bm.id
        let isLifted = drag.liftedID == bm.id
        // 被拖的卡锚在起手槽位（不随数组下标跑），其余卡按当前下标
        let slot = m.origin(index: isDragging ? drag.anchorIndex : index)
        BookmarkCard(bm: bm, cardHeight: cardHeight, fontScale: fontScale)
            .frame(width: m.cellWidth, height: cardHeight)
            // 交互层：透明 UIView 接管点按 / 长按抬起 / 拖动。
            // 不用 SwiftUI .contextMenu：它会跟长按手势抢（菜单一弹出就吃掉长按序列，拖不动）
            .overlay {
                GridDragHandle(
                    onTap: { onTap(bm) },
                    onLift: { drag.lift(bm.id) },
                    onMoved: { now, start, scrollDelta in
                        handleMove(now: now, start: start, scrollDelta: scrollDelta,
                                   metrics: m, list: list, bookmark: bm)
                    },
                    onEnd: { result in
                        switch result {
                        case .finished(let didMove, let point):
                            // 先快照再 end()：end() 会清空临时顺序，顺序反了就永远提交不进去
                            let ordered = drag.orderSnapshot()
                            // 拖过 → 落位（把最终顺序一次性提交给 store），不弹菜单
                            if drag.end() {
                                if didMove, let ordered = ordered {
                                    onReorder(ordered)
                                }
                                return
                            }
                            if didMove { return }
                            drag.setMenuAnchor(point)
                            onMenu(bm)
                        case .aborted:
                            // 手势被系统打断（.cancelled/.failed）：不动数据，丢掉临时顺序
                            _ = drag.end()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // 抬起/拖动：放大 + 投影抬升，跟 iOS 主屏拖图标一个观感。
            // radius 归零而不是 opacity 0：opacity 0 的阴影照样要离屏渲染，一屏几十张卡会掉帧
            .scaleEffect(isDragging ? 1.06 : (isLifted ? 1.03 : 1))
            .shadow(color: .black.opacity(isDragging ? 0.30 : (isLifted ? 0.18 : 0)),
                    radius: isDragging ? 16 : (isLifted ? 10 : 0),
                    x: 0, y: isDragging ? 10 : (isLifted ? 5 : 0))
            .zIndex(isDragging ? 10 : 0)
            .offset(x: slot.x + (isDragging ? drag.offset.width : 0),
                    y: slot.y + (isDragging ? drag.offset.height : 0))
            // 换位动画：被拖的卡关掉动画（它每帧都动，动画只会拖慢跟手）
            .animation(isDragging ? nil : .spring(response: 0.30, dampingFraction: 0.85),
                       value: index)
    }

    private func handleMove(now: CGPoint, start: CGPoint, scrollDelta: CGFloat,
                            metrics m: GridMetrics, list: [Bookmark], bookmark: Bookmark) {
        // 内容坐标系位移 = 手指位移 - 本次拖动期间的滚动量。
        // scrollDelta = contentOffset.y - 起手值（内容上滚为正，卡片要相对补回来才不脱手）
        let dx = now.x - start.x
        let dy = now.y - start.y + scrollDelta

        if drag.draggingID != bookmark.id {
            // 还处于「刚抬起」：越过阈值才算开始拖
            guard drag.liftedID == bookmark.id else { return }
            guard hypot(dx, dy) > 8 else { return }
            let idx = list.firstIndex(where: { $0.id == bookmark.id }) ?? 0
            drag.begin(bookmark.id, index: idx, list: list)
        }
        drag.move(to: CGSize(width: dx, height: dy))

        // 目标槽位 = 起手槽位 + 位移（跟渲染锚点同一套算术，所见即所得）
        let anchor = m.origin(index: drag.anchorIndex)
        let target = m.index(forOffset: CGSize(width: anchor.x + dx, height: anchor.y + dy))
        drag.swap(to: target)
    }
}

// MARK: - 拖动手势层（UIKit）

/// 长按手势的结束方式
enum GridDragEnd {
    /// 正常松手：didMove = 本次是否真的移动过，point = 松手点（窗口坐标）
    case finished(didMove: Bool, point: CGPoint)
    /// 被系统打断（取消/失败），不该有任何后续动作（尤其不能弹菜单）
    case aborted
}

struct GridDragHandle: UIViewRepresentable {
    var onTap: () -> Void
    var onLift: () -> Void
    /// (当前位置, 起手位置, 本次期间滚动量) —— 均为窗口坐标
    var onMoved: (CGPoint, CGPoint, CGFloat) -> Void
    var onEnd: (GridDragEnd) -> Void

    func makeUIView(context: Context) -> GridDragUIView {
        let v = GridDragUIView()
        v.onTap = onTap
        v.onLift = onLift
        v.onMoved = onMoved
        v.onEnd = onEnd
        v.install()
        return v
    }

    func updateUIView(_ v: GridDragUIView, context: Context) {
        v.onTap = onTap
        v.onLift = onLift
        v.onMoved = onMoved
        v.onEnd = onEnd
    }
}

final class GridDragUIView: UIView, UIGestureRecognizerDelegate {
    var onTap: () -> Void = {}
    var onLift: () -> Void = {}
    var onMoved: (CGPoint, CGPoint, CGFloat) -> Void = { _, _, _ in }
    var onEnd: (GridDragEnd) -> Void = { _ in }

    private var installed = false
    private var startPoint: CGPoint = .zero      // 起手点（窗口坐标）
    private var lastPoint: CGPoint = .zero       // 最近手指位置（边缘自动滚动用）
    private var didDrag = false
    private var startOffsetY: CGFloat = 0        // 起手时的 contentOffset.y
    private var autoScrollTimer: Timer?
    /// 长按抬起时临时禁掉外层滚动的 pan（否则抬起后继续滑动会滚页面而不是拖卡）
    private weak var suspendedScrollPan: UIPanGestureRecognizer?

    // 拖到一半视图被移除（切页/退主页）时必须把外层 pan 还回去，
    // 否则主页会「彻底不能滚」。weak 引用 + deinit 兜底是唯一可靠路径
    deinit {
        suspendedScrollPan?.isEnabled = true
    }

    func install() {
        guard !installed else { return }
        installed = true
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // 长按 = 抬起 / 拖动。
        // allowableMovement 只在「识别前」生效（began 之后不再约束），所以给一个正常的 10pt：
        // 手指在 0.35s 内滑超过 10pt（= 想滚动页面）就直接失败不抬起；began 之后手指可以走很远，
        // 拖动不会被这个值打断。设成无限大会让「慢速滚动」在 0.35s 后也抬起卡片并抢走滚动。
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        lp.minimumPressDuration = 0.35
        lp.cancelsTouchesInView = false
        lp.delegate = self
        addGestureRecognizer(lp)

        // 点按：必须等长按失败（长按抬起后松手走菜单，不算点按）
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    // MARK: 手势

    @objc private func handleTap() { onTap() }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            startPoint = currentPoint(g)
            lastPoint = startPoint
            didDrag = false
            startOffsetY = ancestorScrollView?.contentOffset.y ?? 0
            suspendOuterScroll()
            onLift()
            startAutoScroll()
        case .changed:
            let now = currentPoint(g)
            lastPoint = now
            let sc = ancestorScrollView
            let curOffsetY = sc?.contentOffset.y ?? startOffsetY
            let delta = curOffsetY - startOffsetY
            // 外层滚动已经开始动了、而我们还没开始拖 → 老板本来是想滚页面，不是想拖卡。
            // 慢速滚动（起手 0.35s 内位移不足 allowableMovement）也能走到 .began，
            // 这里才算真正的护栏：直接放弃本次抬起，滚动照常，谁也不抢。
            if !didDrag && delta != 0 {
                stopAutoScroll()
                resumeOuterScroll()
                didDrag = false
                onEnd(.aborted)
                return
            }
            if !didDrag && hypot(now.x - startPoint.x, now.y - startPoint.y) > 8 {
                didDrag = true
            }
            onMoved(now, startPoint, delta)
        case .ended:
            finish(g)
        case .cancelled, .failed:
            // .failed 多见于手势被别处抢走：绝不能当松手处理（会误弹菜单）
            stopAutoScroll()
            resumeOuterScroll()
            didDrag = false
            onEnd(.aborted)
        default:
            break
        }
    }

    private func finish(_ g: UIGestureRecognizer) {
        stopAutoScroll()
        resumeOuterScroll()
        onEnd(.finished(didMove: didDrag, point: currentPoint(g)))
        didDrag = false
    }

    /// 手指在窗口坐标系的位置（视图本身在滚动容器里会动，view 坐标不可靠；
    /// UIView 没有 location(in:)，必须问手势要）
    private func currentPoint(_ g: UIGestureRecognizer) -> CGPoint {
        g.location(in: g.view?.window)
    }

    // MARK: 外层滚动

    /// 向上找最近的外层 UIScrollView（主页网格所在的滚动视图）
    private var ancestorScrollView: UIScrollView? {
        var v: UIView? = superview
        while let cur = v {
            if let s = cur as? UIScrollView { return s }
            v = cur.superview
        }
        return nil
    }

    private func suspendOuterScroll() {
        guard let pan = ancestorScrollView?.panGestureRecognizer, pan.isEnabled else { return }
        pan.isEnabled = false
        suspendedScrollPan = pan
    }

    private func resumeOuterScroll() {
        suspendedScrollPan?.isEnabled = true
        suspendedScrollPan = nil
    }

    // MARK: 边缘自动滚动

    private func startAutoScroll() {
        stopAutoScroll()
        guard ancestorScrollView != nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepAutoScroll()
        }
        // common 模式：拖动中 UI 每帧都在动，默认模式会被降频（滚动会一顿一顿）
        RunLoop.main.add(t, forMode: .common)
        autoScrollTimer = t
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func stepAutoScroll() {
        guard let sc = ancestorScrollView else { return }
        // 滚动视图在窗口坐标系里的可见范围
        let frame = sc.convert(sc.bounds, to: nil)
        let band: CGFloat = 72
        let maxStep: CGFloat = 9
        let speed: CGFloat
        if lastPoint.y < frame.minY + band {
            let t = min(1, max(0, (frame.minY + band - lastPoint.y) / band))
            speed = -t * maxStep
        } else if lastPoint.y > frame.maxY - band {
            let t = min(1, max(0, (lastPoint.y - (frame.maxY - band)) / band))
            speed = t * maxStep
        } else {
            return
        }
        let inset = sc.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, sc.contentSize.height - sc.bounds.height + inset.bottom)
        let y = min(maxY, max(minY, sc.contentOffset.y + speed))
        sc.setContentOffset(CGPoint(x: sc.contentOffset.x, y: y), animated: false)
    }

    // MARK: 仲裁

    // 点按必须等长按失败
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        g is UITapGestureRecognizer && other is UILongPressGestureRecognizer
    }

    // 抬起之前允许与外层滚动并存（此时长按还没 began，滚动照常）；
    // 抬起后我们已禁掉外层 pan，这里返回 true 不影响
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - 长按菜单（自绘，不用系统 contextMenu / confirmationDialog）

/// 半透明遮罩 + 一块小玻璃菜单，浮在长按松手处。
/// 不用系统弹层有两个原因：① .contextMenu 会吃掉长按序列导致卡片拖不动；
/// ② 在系统弹层 dismiss 的同时 present sheet 会被 iOS 静默拒绝（已知坑 17c）。
struct BookmarkCardMenu: View {
    /// 松手点，**窗口坐标**（SwiftUI `.global` 空间，与 UIWindow 同原点）；nil = 屏幕中心
    let anchor: CGPoint?
    let onEdit: () -> Void
    let onSplit: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private let menuW: CGFloat = 200
    private let rowH: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            // .global 原点与 anchor 同空间，减掉即本视图内坐标
            let origin = geo.frame(in: .global).origin
            let size = geo.size
            let raw = anchor.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
                ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let menuH = rowH * 3 + 12
            // 贴边留 12pt 安全距，避免菜单跑到屏幕外/圆角外；hi 用 max 兜底窄屏（宽 < 菜单宽）
            let lo = menuW / 2 + 12
            let hi = max(lo, size.width - lo)
            let x = min(max(raw.x, lo), hi)
            let loY = menuH / 2 + 12
            let hiY = max(loY, size.height - loY)
            let y = min(max(raw.y, loY), hiY)
            ZStack(alignment: .topLeading) {
                // 遮罩：点空白取消
                Color.black.opacity(0.18)
                    .onTapGesture(perform: onCancel)
                VStack(spacing: 0) {
                    row("编辑书签", "pencil", onEdit)
                    Divider().opacity(0.4)
                    row("分屏打开", "rectangle.split.2x1", onSplit)
                    Divider().opacity(0.4)
                    row("删除", "trash", onDelete, destructive: true)
                }
                .frame(width: menuW)
                // 工具栏级玻璃：菜单是可操作控件，不用 .clear（见已知坑：.clear 只给媒体上方小控件）
                .launcherGlass(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .position(x: x, y: y)
            }
            .frame(width: size.width, height: size.height)
        }
        // 遮罩要盖满整屏（含状态栏/底部安全区），故整层忽略安全区
        .ignoresSafeArea()
        // transition 必须挂在「条件 if let 产生/销毁的这一个视图」上（调用点的 .animation 配它）
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func row(_ title: String, _ icon: String,
                     _ action: @escaping () -> Void, destructive: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
            }
            // 文字 .primary：菜单叠在遮罩上，tint 蓝会压不住底噪且图标偏色（与底栏同规则）
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: rowH)
            // contentShape：玻璃边缘/字缝的点击会穿透到下层卡片（= 误开书签）
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
