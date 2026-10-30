import AppKit
import SwiftUI

// MARK: - 视觉模型

final class MaskVisualModel: ObservableObject {
    @Published var skin: Skin = SkinPresets.frosted
    @Published var opacity: Double = 0.95
    @Published var peekOpacity: Double = 0.05
    @Published var peeking: Bool = false
    @Published var hovering: Bool = false
    @Published var locked: Bool = false
    @Published var reduceMotion: Bool = false
    @Published var mode: MaskMode = .cover
    @Published var trackMode: TrackMode = .manual
    @Published var trackTitle: String = ""
    @Published var hoverItem: ToolItem? = nil
    @Published var sizeHint: String = ""
    @Published var widgets: [MaskWidget] = []
    @Published var themeID: String = DeviceTheme.departure.id

    var effectiveOpacity: Double { peeking ? peekOpacity : opacity }

    var toolItems: [ToolItem] { ToolItem.items(for: mode) }
}

// MARK: - 悬浮层（工具条 / 边角 / 标签），不吃鼠标事件

struct ChromeLayer: View {
    @ObservedObject var m: MaskVisualModel

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack(alignment: .topLeading) {
                if m.hovering && !m.locked {
                    corners(s)
                    toolbar(s)
                    infoTag(s)
                }
                if m.locked {
                    lockBadge(s)
                }
            }
            .frame(width: s.width, height: s.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func toolbar(_ s: CGSize) -> some View {
        ForEach(ToolbarLayout.rects(in: s, items: m.toolItems), id: \.0.rawValue) { item, r in
            toolButton(item: item, rect: r)
        }
    }

    private func toolButton(item: ToolItem, rect: CGRect) -> some View {
        let active = m.hoverItem == item
        let on = item == .learn && m.mode == .learn
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Color.white.opacity(active ? 0.95 : 0.85) : Color.black.opacity(active ? 0.62 : 0.4))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(active ? 0.55 : 0.2), lineWidth: 0.8)
            Image(systemName: item.symbol(locked: m.locked))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.black.opacity(0.85) : Color.white.opacity(active ? 1 : 0.85))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }

    /// 左上角的状态签：平时写追踪状态，鼠标停在按钮上时写按钮是干什么的
    private func infoTag(_ s: CGSize) -> some View {
        let tip = m.hoverItem.map { $0.tip(mode: m.mode, locked: m.locked) }
        let text = tip ?? (m.trackTitle.isEmpty ? m.trackMode.label : m.trackTitle)
        let room = ToolbarLayout.rects(in: s, items: m.toolItems).first?.1.minX ?? s.width
        let show = room - ToolbarLayout.inset * 2 > 90
        return HStack(spacing: 5) {
            if tip == nil {
                Image(systemName: m.mode == .learn ? "character.book.closed" : m.trackMode.symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if tip == nil && !m.sizeHint.isEmpty {
                Text(m.sizeHint)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 8)
        .frame(height: ToolbarLayout.size - 4)
        .background(
            Capsule().fill(Color.black.opacity(0.45))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
        )
        .frame(maxWidth: max(0, room - ToolbarLayout.inset * 2), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: ToolbarLayout.inset, y: ToolbarLayout.top(in: s) + 2)
        .opacity(show ? 1 : 0)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func corners(_ s: CGSize) -> some View {
        let len: CGFloat = min(14, s.height / 3)
        let inset: CGFloat = 3
        return Path { p in
            p.move(to: CGPoint(x: inset, y: inset + len)); p.addLine(to: CGPoint(x: inset, y: inset)); p.addLine(to: CGPoint(x: inset + len, y: inset))
            p.move(to: CGPoint(x: s.width - inset - len, y: inset)); p.addLine(to: CGPoint(x: s.width - inset, y: inset)); p.addLine(to: CGPoint(x: s.width - inset, y: inset + len))
            p.move(to: CGPoint(x: inset, y: s.height - inset - len)); p.addLine(to: CGPoint(x: inset, y: s.height - inset)); p.addLine(to: CGPoint(x: inset + len, y: s.height - inset))
            p.move(to: CGPoint(x: s.width - inset - len, y: s.height - inset)); p.addLine(to: CGPoint(x: s.width - inset, y: s.height - inset)); p.addLine(to: CGPoint(x: s.width - inset, y: s.height - inset - len))
        }
        .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        .shadow(color: .black.opacity(0.6), radius: 3)
    }

    private func lockBadge(_ s: CGSize) -> some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(4)
            .background(Circle().fill(Color.black.opacity(0.35)))
            .position(x: s.width - 14, y: min(14, s.height / 2))
    }
}

/// 外发光只画在条身外面。阴影要是直接挂在半透明的着色层上，
/// 条身里面也会透出一层阴影，整条玻璃就被压暗了。
struct GlowLayer: View {
    let skin: Skin
    let opacity: Double

    var body: some View {
        Canvas { gc, size in
            let r = min(skin.glowRadius, Skin.maxGlow)
            guard r > 0.5, skin.glowColor.a > 0.01 else { return }
            let bar = CGRect(origin: .zero, size: size).insetBy(dx: maskPad, dy: maskPad)
            guard bar.width > 2, bar.height > 2 else { return }
            let shape = Path(roundedRect: bar, cornerRadius: Skin.clampRadius(skin.cornerRadius, bar.size), style: .circular)
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addPath(shape)
            gc.clip(to: outside, style: FillStyle(eoFill: true))
            gc.addFilter(.shadow(color: skin.glowColor.color, radius: r, x: 0, y: r * 0.18))
            gc.fill(shape, with: .color(.black))
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

struct MaskVisual: View {
    @ObservedObject var m: MaskVisualModel

    var body: some View {
        ZStack {
            GlowLayer(skin: m.skin, opacity: m.effectiveOpacity)
            ZStack {
                SkinLayer(skin: m.skin, opacity: m.effectiveOpacity, reduceMotion: m.reduceMotion)
                WidgetLayer(widgets: m.widgets, themeID: m.themeID,
                            opacity: m.peeking ? m.peekOpacity : 1.0)
                ChromeLayer(m: m)
            }
            .padding(maskPad)
        }
        .animation(.easeOut(duration: 0.14), value: m.peeking)
        .animation(.easeOut(duration: 0.12), value: m.hovering)
    }
}

// MARK: - 玻璃

/// 背景模糊。系统材质在模糊上面还叠了一层灰、一层提亮和一层桌面色，
/// pure 时把这几层藏掉、饱和度还原，只留模糊本身；半径也能自己定。
/// 这些是 NSVisualEffectView 里的图层，AppKit 换材质、换外观时会重建，所以每次 layout 都重新套一遍。
final class GlassView: NSVisualEffectView {
    var pure = false
    /// 0 用系统材质自带的半径
    var radius: Double = 0
    /// 乘在系统饱和度上；pure 时直接当饱和度用
    var saturation: Double = 1
    var featherX: CGFloat = 0
    var featherY: CGFloat = 0
    var cornerRadius: CGFloat = 0

    /// 各材质原本的半径和饱和度，换回系统值时要用
    private var stock: [String: (radius: Double, saturation: Double)] = [:]
    private var maskKey = ""

    override func layout() {
        super.layout()
        applyTweaks()
        applyMask()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    func refresh() {
        maskKey = ""
        needsLayout = true
        layoutSubtreeIfNeeded()
        applyTweaks()
        applyMask()
    }

    private func applyTweaks() {
        guard let root = layer else { return }
        for mat in root.sublayers ?? [] {
            guard let subs = mat.sublayers,
                  let backdrop = subs.first(where: { $0.name == "backdrop" }) else { continue }
            let key = mat.name ?? "?"
            if stock[key] == nil {
                let blur = backdrop.value(forKeyPath: "filters.gaussianBlur.inputRadius") as? Double ?? 30
                let sat = backdrop.value(forKeyPath: "filters.colorSaturate.inputAmount") as? Double ?? 1
                stock[key] = (blur, sat)
            }
            let base = stock[key]!
            backdrop.setValue(radius > 0 ? radius : base.radius, forKeyPath: "filters.gaussianBlur.inputRadius")
            backdrop.setValue((pure ? 1.0 : base.saturation) * saturation, forKeyPath: "filters.colorSaturate.inputAmount")
            for l in subs where l !== backdrop { l.isHidden = pure }
        }
    }

    private func applyMask() {
        let size = bounds.size
        let key = "\(size.width)x\(size.height) \(featherX) \(featherY) \(cornerRadius)"
        guard key != maskKey, size.width > 1, size.height > 1 else { return }
        maskKey = key
        if featherX > 0.5 || featherY > 0.5 {
            // maskImage 只认硬边，羽化要挂在图层的 mask 上
            maskImage = nil
            layer?.mask = GlassView.featherLayer(size: size, fx: min(featherX, size.width / 2 - 1),
                                                 fy: min(featherY, size.height / 2 - 1))
        } else {
            layer?.mask = nil
            maskImage = GlassView.roundedMask(radius: Skin.clampRadius(Double(cornerRadius), size))
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage? {
        guard radius > 0.5 else { return nil }
        let d = radius * 2 + 2
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    /// 四边 smoothstep 渐隐的遮罩，中间一像素拉伸铺满
    static func featherLayer(size: CGSize, fx: CGFloat, fy: CGFloat) -> CALayer {
        let fx = max(0, fx), fy = max(0, fy)
        let scale: CGFloat = 2
        let W = Int((fx * 2 + 2) * scale), H = Int((fy * 2 + 2) * scale)
        var px = [UInt8](repeating: 0, count: W * H * 4)
        func ss(_ t: CGFloat) -> CGFloat { let x = max(0, min(1, t)); return x * x * (3 - 2 * x) }
        let w = CGFloat(W) / scale, h = CGFloat(H) / scale
        for j in 0..<H {
            for i in 0..<W {
                let x = (CGFloat(i) + 0.5) / scale, y = (CGFloat(j) + 0.5) / scale
                let ax = fx > 0 ? ss(min(x, w - x) / fx) : 1
                let ay = fy > 0 ? ss(min(y, h - y) / fy) : 1
                px[(j * W + i) * 4 + 3] = UInt8(max(0, min(255, ax * ay * 255)))
            }
        }
        let m = CALayer()
        m.frame = CGRect(origin: .zero, size: size)
        if let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let img = ctx.makeImage() {
            m.contents = img
            m.contentsScale = scale
            m.contentsCenter = CGRect(x: fx / w, y: fy / h, width: 2 / w, height: 2 / h)
        } else {
            m.backgroundColor = NSColor.black.cgColor
        }
        return m
    }
}

// MARK: - 事件不拦截的 hosting view

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 交互根视图（全部鼠标逻辑在 AppKit 侧）

@MainActor
protocol MaskRootDelegate: AnyObject {
    func maskRootFrameChanged(_ v: MaskRootView, live: Bool)
    func maskRootClicked(_ v: MaskRootView, item: ToolItem)
    func maskRootContextMenu(_ v: MaskRootView, at screenPoint: NSPoint)
}

enum DragZone {
    case move
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .move: return .openHand
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

final class MaskRootView: NSView {
    weak var delegate: MaskRootDelegate?
    let model: MaskVisualModel
    var snapEnabled = true

    private let glass = GlassView()
    private var host: PassthroughHostingView<MaskVisual>!
    private var tracking: NSTrackingArea?
    private var dragZone: DragZone = .move
    private(set) var dragging = false
    private var startMouse: NSPoint = .zero
    private var startFrame: NSRect = .zero
    private var pressedItem: ToolItem?

    override var isFlipped: Bool { true }

    /// 条身所在的矩形；四周留出 maskPad 给外发光
    var contentRect: NSRect { bounds.insetBy(dx: maskPad, dy: maskPad) }

    init(model: MaskVisualModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true

        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = []
        addSubview(glass)

        host = PassthroughHostingView(rootView: MaskVisual(m: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glass.frame = contentRect
    }

    // MARK: 玻璃层（真正的背景模糊，必须留在 AppKit 里）

    func applyBlur(skin: Skin, alpha: CGFloat, animated: Bool) {
        glass.isHidden = !skin.blur
        guard skin.blur else { return }
        glass.material = skin.material.material
        glass.appearance = skin.appearance.appearance
        glass.pure = skin.pureBlur
        glass.radius = skin.blurRadius
        glass.saturation = skin.blurSaturation
        glass.featherX = CGFloat(skin.feather)
        glass.featherY = CGFloat(min(4, skin.feather * 0.15))
        glass.cornerRadius = CGFloat(skin.cornerRadius)
        glass.refresh()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                glass.animator().alphaValue = alpha
            }
        } else {
            glass.alphaValue = alpha
        }
    }

    // MARK: 命中范围

    /// 条身连同四边的拖拽热区，屏幕坐标
    var liveScreenRect: CGRect {
        guard let w = window else { return .zero }
        return w.frame.insetBy(dx: maskPad - ToolbarLayout.edgeHot, dy: maskPad - ToolbarLayout.edgeHot)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let p = convert(point, from: sv)
        let live = contentRect.insetBy(dx: -ToolbarLayout.edgeHot, dy: -ToolbarLayout.edgeHot)
        return live.contains(p) ? self : nil
    }

    // MARK: 跟踪区域

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: contentRect.insetBy(dx: -ToolbarLayout.edgeHot, dy: -ToolbarLayout.edgeHot),
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        model.hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    func endHover() {
        guard !dragging else { return }
        if model.hovering { model.hovering = false }
        if model.hoverItem != nil { model.hoverItem = nil }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = local(event)
        if !model.hovering { model.hovering = true }
        let item = ToolbarLayout.hit(p, in: contentRect.size, items: model.toolItems)
        if item != model.hoverItem { model.hoverItem = item }
        if item != nil {
            NSCursor.pointingHand.set()
        } else {
            zone(at: p).cursor.set()
        }
    }

    /// 事件点转成「条身内」坐标
    private func local(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x - contentRect.minX, y: p.y - contentRect.minY)
    }

    // MARK: 区域判定

    private func zone(at p: CGPoint) -> DragZone {
        let e = ToolbarLayout.edgeHot
        let s = contentRect.size
        let left = p.x <= e
        let right = p.x >= s.width - e
        let top = p.y <= e
        let bottom = p.y >= s.height - e
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .move
        }
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        let p = local(event)
        if let item = ToolbarLayout.hit(p, in: contentRect.size, items: model.toolItems) {
            pressedItem = item
            return
        }
        pressedItem = nil
        dragZone = zone(at: p)
        dragging = true
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
        if dragZone == .move { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        let dy = now.y - startMouse.y
        var f = startFrame

        switch dragZone {
        case .move:
            f.origin.x += dx
            f.origin.y += dy
        case .left:
            f.origin.x += dx; f.size.width -= dx
        case .right:
            f.size.width += dx
        case .bottom:
            f.origin.y += dy; f.size.height -= dy
        case .top:
            f.size.height += dy
        case .bottomLeft:
            f.origin.x += dx; f.size.width -= dx; f.origin.y += dy; f.size.height -= dy
        case .bottomRight:
            f.size.width += dx; f.origin.y += dy; f.size.height -= dy
        case .topLeft:
            f.origin.x += dx; f.size.width -= dx; f.size.height += dy
        case .topRight:
            f.size.width += dx; f.size.height += dy
        }

        f.size.width = max(minBarSize.width + maskPad * 2, f.size.width)
        f.size.height = max(minBarSize.height + maskPad * 2, f.size.height)
        if dragZone == .move, snapEnabled { f = snapped(f) }

        win.setFrame(f, display: true)
        let visual = f.insetBy(dx: maskPad, dy: maskPad)
        model.sizeHint = "\(Int(visual.width))×\(Int(visual.height))"
        delegate?.maskRootFrameChanged(self, live: true)
    }

    override func mouseUp(with event: NSEvent) {
        if let item = pressedItem {
            let p = local(event)
            if ToolbarLayout.hit(p, in: contentRect.size, items: model.toolItems) == item {
                delegate?.maskRootClicked(self, item: item)
            }
            pressedItem = nil
            return
        }
        if dragging {
            dragging = false
            model.sizeHint = ""
            delegate?.maskRootFrameChanged(self, live: false)
            NSCursor.openHand.set()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.maskRootContextMenu(self, at: NSEvent.mouseLocation)
    }

    // MARK: 吸附（按条身算，不算发光留白）

    private func snapped(_ panelFrame: NSRect) -> NSRect {
        let f = panelFrame.insetBy(dx: maskPad, dy: maskPad)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(f) }) ?? NSScreen.main else {
            return panelFrame
        }
        let v = screen.visibleFrame
        let full = screen.frame
        let t: CGFloat = 14
        var r = f
        if abs(r.minX - full.minX) < t { r.origin.x = full.minX }
        if abs(r.maxX - full.maxX) < t { r.origin.x = full.maxX - r.width }
        if abs(r.minY - full.minY) < t { r.origin.y = full.minY }
        if abs(r.maxY - v.maxY) < t { r.origin.y = v.maxY - r.height }
        if abs(r.midX - full.midX) < t { r.origin.x = full.midX - r.width / 2 }
        return r.insetBy(dx: -maskPad, dy: -maskPad)
    }
}

// MARK: - 面板

/// 条身四周留出的透明边，给外发光用。发光半径夹在 Skin.maxGlow 以内，
/// 高斯阴影大约在 1.5 倍半径处才淡到看不见，再加上往下的偏移，48 刚好不裁出硬边。
let maskPad: CGFloat = 48

/// 条身最小尺寸
let minBarSize = CGSize(width: 70, height: 22)

final class MaskPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
