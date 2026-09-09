import AppKit
import CoreImage
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
    @Published var trackMode: TrackMode = .manual
    @Published var trackTitle: String = ""
    @Published var hoverItem: ToolItem? = nil
    @Published var sizeHint: String = ""
    @Published var widgets: [MaskWidget] = []

    var effectiveOpacity: Double { peeking ? peekOpacity : opacity }
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
            .frame(width: s.width, height: s.height)
        }
        .allowsHitTesting(false)
    }

    private func toolbar(_ s: CGSize) -> some View {
        ForEach(ToolbarLayout.rects(in: s), id: \.0.rawValue) { item, r in
            toolButton(item: item, rect: r)
        }
    }

    private func toolButton(item: ToolItem, rect: CGRect) -> some View {
        let active = m.hoverItem == item
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(active ? 0.55 : 0.32))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(active ? 0.55 : 0.18), lineWidth: 0.8)
            Image(systemName: item == .lock && m.locked ? "lock.fill" : item.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(active ? 1 : 0.82))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    private func infoTag(_ s: CGSize) -> some View {
        let text = m.trackTitle.isEmpty ? m.trackMode.label : m.trackTitle
        let show = s.width > 320 && s.height > 40
        return HStack(spacing: 5) {
            Image(systemName: m.trackMode.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
            if !m.sizeHint.isEmpty {
                Text(m.sizeHint)
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.black.opacity(0.38))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
        )
        .position(x: 0, y: 0)
        .offset(x: ToolbarLayout.inset + 60, y: ToolbarLayout.inset + 11)
        .opacity(show ? 1 : 0)
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
    }

    private func corners(_ s: CGSize) -> some View {
        let len: CGFloat = 14
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
            .position(x: s.width - 14, y: 14)
    }
}

struct MaskVisual: View {
    @ObservedObject var m: MaskVisualModel

    var body: some View {
        ZStack {
            SkinLayer(skin: m.skin, opacity: m.effectiveOpacity, reduceMotion: m.reduceMotion)
            WidgetLayer(widgets: m.widgets, opacity: m.peeking ? m.peekOpacity : 1.0)
            ChromeLayer(m: m)
        }
        .padding(maskPad)
        .animation(.easeOut(duration: 0.14), value: m.peeking)
        .animation(.easeOut(duration: 0.12), value: m.hovering)
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

    private let blurView = NSVisualEffectView()
    private var host: PassthroughHostingView<MaskVisual>!
    private var tracking: NSTrackingArea?
    private var dragZone: DragZone = .move
    private var dragging = false
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

        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = []
        addSubview(blurView)

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

    private var lastMaskSize: CGSize = .zero

    override func layout() {
        super.layout()
        blurView.frame = contentRect
        if contentRect.size != lastMaskSize {
            lastMaskSize = contentRect.size
            blurView.maskImage = MaskRootView.roundedMask(
                radius: Skin.clampRadius(model.skin.cornerRadius, contentRect.size))
        }
    }

    // MARK: 玻璃层（真正的背景模糊，必须留在 AppKit 里）

    func applyBlur(skin: Skin, alpha: CGFloat, animated: Bool) {
        blurView.isHidden = !skin.blur
        guard skin.blur else { return }
        blurView.material = skin.material.material
        blurView.appearance = skin.appearance.appearance
        blurView.maskImage = MaskRootView.roundedMask(radius: Skin.clampRadius(skin.cornerRadius, contentRect.size))
        if abs(skin.blurSaturation - 1) > 0.02 {
            let f = CIFilter(name: "CIColorControls",
                             parameters: ["inputSaturation": skin.blurSaturation])
            blurView.layer?.filters = f.map { [$0] } ?? []
        } else {
            blurView.layer?.filters = []
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                blurView.animator().alphaValue = alpha
            }
        } else {
            blurView.alphaValue = alpha
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

    // MARK: 命中范围

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
        model.hovering = false
        model.hoverItem = nil
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = local(event)
        model.hovering = true
        let item = ToolbarLayout.hit(p, in: contentRect.size)
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
        if let item = ToolbarLayout.hit(p, in: contentRect.size) {
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

        f.size.width = max(70 + maskPad * 2, f.size.width)
        f.size.height = max(26 + maskPad * 2, f.size.height)
        if dragZone == .move, snapEnabled { f = snapped(f) }

        win.setFrame(f, display: true)
        let visual = f.insetBy(dx: maskPad, dy: maskPad)
        model.sizeHint = "\(Int(visual.width))×\(Int(visual.height))"
        delegate?.maskRootFrameChanged(self, live: true)
    }

    override func mouseUp(with event: NSEvent) {
        if let item = pressedItem {
            let p = local(event)
            if ToolbarLayout.hit(p, in: contentRect.size) == item {
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

/// 条身四周留出的透明边，给外发光和阴影用
let maskPad: CGFloat = 24

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
