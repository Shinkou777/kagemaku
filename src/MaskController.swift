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

    init(config: MaskConfig, app: AppDelegate) {
        self.config = config
        self.app = app
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

    // MARK: 应用配置

    func applyAll() {
        let store = Store.shared
        model.skin = store.skin(config.skinID)
        model.opacity = config.opacity
        model.peekOpacity = store.settings.peekOpacity
        model.reduceMotion = store.settings.reduceMotion
        model.locked = config.locked
        model.trackMode = config.trackMode
        model.trackTitle = trackTitle()
        if model.widgets != config.widgets { model.widgets = config.widgets }
        if model.themeID != config.themeID { model.themeID = config.themeID }
        root.snapEnabled = store.settings.snapEdges
        panel.ignoresMouseEvents = config.locked
        panel.level = store.settings.aboveFullscreen ? .screenSaver : .floating
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
            return "手动摆放"
        case .window:
            if lostWindow { return "窗口已关闭" }
            return "跟随 " + (config.trackWindowOwner ?? "未选择窗口")
        case .subtitle:
            return detectFailures > 3 ? "未检出字幕" : "自动吸附字幕"
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
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
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
        model.skin = Store.shared.skin(id)
        syncBlur(animated: false)
    }

    func setOpacity(_ v: Double) {
        config.opacity = v
        Store.shared.update(config)
        model.opacity = v
        syncBlur(animated: false)
    }

    func setTrackMode(_ mode: TrackMode, windowID: UInt32? = nil, owner: String? = nil) {
        config.trackMode = mode
        detectFailures = 0
        lostWindow = false
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
        f.size.width = max(70, f.size.width)
        f.size.height = max(26, f.size.height)
        panel.setFrame(MaskController.panelRect(f), display: true)
        config.frame = f
        Store.shared.update(config)
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
                            width: max(70, CGFloat(config.anchorW) * wb.width),
                            height: max(26, CGFloat(config.anchorH) * wb.height))
        let cur = visualFrame
        if abs(cur.minX - target.minX) > 0.5 || abs(cur.minY - target.minY) > 0.5
            || abs(cur.width - target.width) > 0.5 || abs(cur.height - target.height) > 0.5 {
            panel.setFrame(MaskController.panelRect(target), display: true)
            config.frame = target
        }
    }

    // MARK: 自动吸附字幕

    func searchBand() -> CGRect {
        let f = visualFrame
        let band = CGFloat(Store.shared.settings.detectBand)
        return CGRect(x: f.minX, y: f.midY - band / 2, width: f.width, height: band)
    }

    func applyDetected(range: ClosedRange<CGFloat>) {
        let pad = CGFloat(Store.shared.settings.detectPadding)
        let f = visualFrame
        let newY = range.lowerBound - pad
        let newH = max(26, (range.upperBound - range.lowerBound) + pad * 2)
        if abs(newY - f.minY) < 3 && abs(newH - f.height) < 3 { return }
        let target = CGRect(x: f.minX, y: newY, width: f.width, height: newH)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(MaskController.panelRect(target), display: true)
        }
        config.frame = target
        Store.shared.update(config)
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
            Store.shared.update(config)
            if config.trackMode == .window { recomputeAnchor() }
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
