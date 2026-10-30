import AppKit
import SwiftUI

@MainActor
final class MaskController: NSObject, MaskRootDelegate {

    var config: MaskConfig
    let model = MaskVisualModel()
    let panel: MaskPanel
    let root: MaskRootView
    weak var app: AppDelegate?

    private var detectFailures = 0
    private var lostWindow = false
    /// 认字模型还没跑完第一次
    var warming = false

    /// 最近几秒认到的字幕范围，玻璃按它定位置
    private let snap = SnapTracker()
    /// 用户自己摆的左右范围。学外语时玻璃只为长句往外扩，句子短了就退回这里
    private var baseX: ClosedRange<CGFloat>
    /// 刚拖过：第一次对齐不限距离，拖到字幕附近就能吸上去
    private var freshDrag = true

    init(config: MaskConfig, app: AppDelegate) {
        self.config = config
        self.app = app
        self.baseX = config.frame.minX...config.frame.maxX
        self.panel = MaskPanel(frame: MaskController.panelRect(config.frame))
        self.root = MaskRootView(model: model)
        super.init()
        root.delegate = self
        panel.contentView = root
        applyAll()
        if !config.hidden {
            panel.orderFrontRegardless()
        }
    }

    // MARK: 坐标：config.frame 是条身，panel 比它四周各大 maskPad

    static func panelRect(_ visual: CGRect) -> CGRect {
        visual.insetBy(dx: -maskPad, dy: -maskPad)
    }

    var visualFrame: CGRect {
        panel.frame.insetBy(dx: maskPad, dy: maskPad)
    }

    var windowNumber: CGWindowID {
        CGWindowID(max(0, panel.windowNumber))
    }

    var isDragging: Bool { root.dragging }

    var wantsDetection: Bool { config.trackMode == .subtitle && !config.hidden }

    // MARK: 应用配置

    /// 学外语时用固定的透明玻璃，半径跟着玻璃高度走
    private func effectiveSkin(height: CGFloat? = nil) -> Skin {
        let store = Store.shared
        if config.mode == .learn {
            return SkinPresets.learn(height: height ?? config.frame.height, strength: store.settings.learnBlur)
        }
        return store.skin(config.skinID)
    }

    func applyAll() {
        let store = Store.shared
        model.skin = effectiveSkin()
        model.opacity = config.mode == .learn ? 1 : config.opacity
        model.peekOpacity = store.settings.peekOpacity
        model.reduceMotion = store.settings.reduceMotion
        model.locked = config.locked
        model.mode = config.mode
        model.trackMode = config.trackMode
        model.trackTitle = trackTitle()
        let widgets = config.mode == .learn ? [] : config.widgets
        if model.widgets != widgets { model.widgets = widgets }
        if model.themeID != config.themeID { model.themeID = config.themeID }
        root.snapEnabled = store.settings.snapEdges
        panel.ignoresMouseEvents = config.locked
        if !(app?.panelsLowered ?? false) {
            panel.level = store.settings.aboveFullscreen ? .screenSaver : .floating
        }
        let want = MaskController.panelRect(config.frame)
        if panel.frame != want {
            panel.setFrame(want, display: true)
        }
        syncBlur(animated: false)
        if config.hidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func syncBlur(animated: Bool) {
        root.applyBlur(skin: model.skin, alpha: CGFloat(model.effectiveOpacity), animated: animated)
    }

    private func trackTitle() -> String {
        switch config.trackMode {
        case .manual:
            return config.mode == .learn ? "学外语　手动摆放" : "手动摆放"
        case .window:
            if lostWindow { return "窗口已关闭" }
            return "跟随 " + (config.trackWindowOwner ?? "未选择窗口")
        case .subtitle:
            if warming { return "正在准备认字，第一次要十几秒" }
            if detectFailures > 3 {
                return config.mode == .learn ? "附近没认出中文字幕" : "附近没认出字幕"
            }
            return config.mode == .learn ? "学外语　对齐中文行" : "自动对齐字幕"
        }
    }

    func refreshTitle() {
        let t = trackTitle()
        if model.trackTitle != t { model.trackTitle = t }
    }

    // MARK: 状态切换

    func setPeek(_ on: Bool) {
        model.peekOpacity = Store.shared.settings.peekOpacity
        model.peeking = on
        syncBlur(animated: true)
    }

    func setHidden(_ hidden: Bool) {
        config.hidden = hidden
        Store.shared.update(config)
        if hidden {
            root.endHover()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        app?.restartDetectTimer()
    }

    func setLocked(_ locked: Bool) {
        config.locked = locked
        Store.shared.update(config)
        model.locked = locked
        panel.ignoresMouseEvents = locked
        if locked {
            model.hovering = false
            model.hoverItem = nil
        }
    }

    func setSkin(_ id: UUID) {
        config.skinID = id
        Store.shared.update(config)
        guard config.mode == .cover else { return }
        model.skin = Store.shared.skin(id)
        syncBlur(animated: false)
    }

    func setOpacity(_ v: Double) {
        config.opacity = v
        Store.shared.update(config)
        guard config.mode == .cover else { return }
        model.opacity = v
        syncBlur(animated: false)
    }

    /// 切到学外语时顺手打开自动对齐：要盖的是中文那一行，得先认出它在哪
    func setMode(_ mode: MaskMode) {
        guard config.mode != mode else { return }
        config.mode = mode
        if mode == .learn && config.trackMode == .manual {
            config.trackMode = .subtitle
        }
        snap.reset()
        freshDrag = true
        baseX = visualFrame.minX...visualFrame.maxX
        detectFailures = 0
        Store.shared.update(config)
        applyAll()
        app?.restartDetectTimer()
    }

    func setTrackMode(_ mode: TrackMode, windowID: UInt32? = nil, owner: String? = nil) {
        config.trackMode = mode
        detectFailures = 0
        lostWindow = false
        snap.reset()
        freshDrag = true
        if mode == .window {
            config.trackWindowID = windowID ?? config.trackWindowID
            config.trackWindowOwner = owner ?? config.trackWindowOwner
            recomputeAnchor()
        }
        Store.shared.update(config)
        model.trackMode = mode
        refreshTitle()
    }

    func setFrame(_ visual: CGRect) {
        var f = visual
        f.size.width = max(minBarSize.width, f.size.width)
        f.size.height = max(minBarSize.height, f.size.height)
        panel.setFrame(MaskController.panelRect(f), display: true)
        config.frame = f
        baseX = f.minX...f.maxX
        snap.reset()
        freshDrag = true
        Store.shared.update(config)
        refreshLearnSkin()
    }

    /// 学外语玻璃的模糊半径按高度算，高度变了要重算
    private func refreshLearnSkin() {
        guard config.mode == .learn else { return }
        let s = effectiveSkin(height: visualFrame.height)
        if s != model.skin {
            model.skin = s
            syncBlur(animated: false)
        }
    }

    // MARK: 鼠标穿透

    static let pinChrome = Store.testDataDir != nil && ProcessInfo.processInfo.environment["KAGEMAKU_PIN_CHROME"] == "1"

    /// 条身四周那圈透明边上画着外发光，窗口会把那里的点击吃掉。
    /// 鼠标不在条身上时整块面板设成穿透，底下播放器的进度条照点。
    func tickMouse() {
        guard !config.hidden, panel.isVisible else { return }
        if config.locked {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        if root.dragging { return }
        // 测试截图时让工具条一直亮着
        if MaskController.pinChrome { if !model.hovering { model.hovering = true }; return }
        let inside = root.liveScreenRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if !inside { root.endHover() }
    }

    // MARK: 跟随窗口

    func recomputeAnchor() {
        guard let id = config.trackWindowID, let wb = WindowTracker.bounds(of: id),
              wb.width > 1, wb.height > 1 else { return }
        let f = visualFrame
        config.anchorX = Double((f.minX - wb.minX) / wb.width)
        config.anchorY = Double((f.minY - wb.minY) / wb.height)
        config.anchorW = Double(f.width / wb.width)
        config.anchorH = Double(f.height / wb.height)
        Store.shared.update(config)
    }

    func tickWindowFollow() {
        guard config.trackMode == .window, !config.hidden, let id = config.trackWindowID else { return }
        guard let wb = WindowTracker.bounds(of: id) else {
            if !lostWindow { lostWindow = true; refreshTitle() }
            return
        }
        if lostWindow { lostWindow = false; refreshTitle() }
        let target = CGRect(x: wb.minX + CGFloat(config.anchorX) * wb.width,
                            y: wb.minY + CGFloat(config.anchorY) * wb.height,
                            width: max(minBarSize.width, CGFloat(config.anchorW) * wb.width),
                            height: max(minBarSize.height, CGFloat(config.anchorH) * wb.height))
        let cur = visualFrame
        if abs(cur.minX - target.minX) > 0.5 || abs(cur.minY - target.minY) > 0.5
            || abs(cur.width - target.width) > 0.5 || abs(cur.height - target.height) > 0.5 {
            panel.setFrame(MaskController.panelRect(target), display: true)
            config.frame = target
            baseX = target.minX...target.maxX
        }
    }

    // MARK: 自动对齐字幕

    /// 以条身为中心上下放宽，左右各多看 15%。学外语的玻璃很薄，上下至少各留 60 点，才看得见旁边的外文行
    func searchBand() -> CGRect {
        let f = visualFrame
        let h = max(CGFloat(Store.shared.settings.detectBand), f.height + 120)
        let padX = f.width * 0.15
        return CGRect(x: f.minX - padX, y: f.midY - h / 2, width: f.width + padX * 2, height: h)
    }

    func applyReading(_ lines: [TextLine]) {
        if warming { warming = false; refreshTitle() }
        guard !root.dragging else { return }
        let bar = visualFrame
        guard let pick = SubtitleLayout.pick(lines, mode: config.mode, near: bar, loose: freshDrag) else {
            noteDetect(success: false)
            return
        }
        freshDrag = false
        snap.add(pick)
        noteDetect(success: true)

        let skin = effectiveSkin()
        let fx = CGFloat(skin.feather), fy = CGFloat(min(4, skin.feather * 0.15))
        guard var target = snap.target(mode: config.mode, baseX: baseX,
                                       padding: CGFloat(Store.shared.settings.detectPadding),
                                       featherX: fx, featherY: fy) else { return }
        target.size.width = max(minBarSize.width, target.width)
        target.size.height = max(minBarSize.height, target.height)
        // 不让玻璃被推出屏幕
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar) }) {
            target = target.intersection(screen.frame.insetBy(dx: -1, dy: -1))
            guard !target.isNull, target.width >= minBarSize.width, target.height >= minBarSize.height else { return }
        }
        let moved = abs(target.minX - bar.minX) > 1.5 || abs(target.maxX - bar.maxX) > 1.5
            || abs(target.minY - bar.minY) > 1.5 || abs(target.maxY - bar.maxY) > 1.5
        guard moved else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(MaskController.panelRect(target), display: true)
        }
        config.frame = target
        Store.shared.update(config)
        refreshLearnSkin()
    }

    func noteDetect(success: Bool) {
        if success {
            if detectFailures != 0 { detectFailures = 0; refreshTitle() }
        } else {
            detectFailures += 1
            if detectFailures == 4 { refreshTitle() }
        }
    }

    // MARK: MaskRootDelegate

    func maskRootFrameChanged(_ v: MaskRootView, live: Bool) {
        config.frame = visualFrame
        if !live {
            baseX = config.frame.minX...config.frame.maxX
            snap.reset()
            freshDrag = true
            Store.shared.update(config)
            if config.trackMode == .window { recomputeAnchor() }
            refreshLearnSkin()
        }
        Store.shared.activeMaskID = config.id
    }

    func maskRootClicked(_ v: MaskRootView, item: ToolItem) {
        Store.shared.activeMaskID = config.id
        app?.handleToolClick(item, on: self)
    }

    func maskRootContextMenu(_ v: MaskRootView, at screenPoint: NSPoint) {
        Store.shared.activeMaskID = config.id
        app?.showContextMenu(for: self, at: screenPoint)
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
