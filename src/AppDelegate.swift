import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private(set) var controllers: [MaskController] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var followTimer: Timer?
    private var detectTimer: Timer?
    private let detector = SubtitleDetector()
    private var peeking = false
    private var permissionAlertShown = false

    var store: Store { Store.shared }

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        rebuildControllers()
        registerHotkeys()
        startTimers()
        DataHub.shared.register(store.masks.flatMap { $0.widgets })

        if !UserDefaults.standard.bool(forKey: "kagemaku.welcomed") {
            UserDefaults.standard.set(true, forKey: "kagemaku.welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        HotkeyManager.shared.unregisterAll()
    }

    // MARK: 遮挡条

    func rebuildControllers() {
        for c in controllers { c.close() }
        controllers = store.masks.map { MaskController(config: $0, app: self) }
        rescueOffscreen()
    }

    func controller(_ id: UUID) -> MaskController? {
        controllers.first { $0.config.id == id }
    }

    var activeController: MaskController? {
        if let id = store.activeMaskID, let c = controller(id) { return c }
        return controllers.first
    }

    func addMask() {
        var m = store.defaultMask()
        if let last = controllers.last {
            m.frame = last.panel.frame.offsetBy(dx: 26, dy: -26)
            m.skinID = last.config.skinID
            m.opacity = last.config.opacity
        }
        m.label = "遮挡条 \(store.masks.count + 1)"
        store.masks.append(m)
        store.save()
        let c = MaskController(config: m, app: self)
        controllers.append(c)
        store.activeMaskID = m.id
    }

    func removeMask(_ c: MaskController) {
        lastClosed = c.config
        c.close()
        controllers.removeAll { $0 === c }
        store.masks.removeAll { $0.id == c.config.id }
        store.activeMaskID = store.masks.first?.id
        store.save()
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
    }

    /// 关掉的最后一条，随时能放回来
    private var lastClosed: MaskConfig?

    func undoClose() {
        guard var m = lastClosed else { return }
        lastClosed = nil
        m.id = UUID()
        m.hidden = false
        store.masks.append(m)
        store.save()
        let c = MaskController(config: m, app: self)
        controllers.append(c)
        store.activeMaskID = m.id
        rescueOffscreen()
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
    }

    /// 只刷视觉，不动窗口位置和定时器（拖滑块时用）
    func refreshVisuals() {
        for c in controllers {
            if let cfg = store.mask(c.config.id) { c.config = cfg }
            c.model.skin = store.skin(c.config.skinID)
            c.model.opacity = c.config.opacity
            c.model.peekOpacity = store.settings.peekOpacity
            c.model.reduceMotion = store.settings.reduceMotion
            c.model.widgets = c.config.widgets
            c.model.themeID = c.config.themeID
            c.syncBlur(animated: false)
        }
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
    }

    /// 摆回当前屏幕中下方，条被拖出屏幕时用
    func resetPosition(_ c: MaskController) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.frame
        let w = min(1000, f.width * 0.62)
        let h = max(60, min(160, c.config.frame.height))
        c.setFrame(CGRect(x: f.midX - w / 2, y: f.minY + f.height * 0.11, width: w, height: h))
        if c.config.trackMode == .window { c.recomputeAnchor() }
    }

    /// 完全飘到屏幕外的条拉回来
    private func rescueOffscreen() {
        for c in controllers {
            let f = c.config.frame
            let visible = NSScreen.screens.contains { $0.frame.intersection(f).width > 120 }
            if !visible { resetPosition(c) }
        }
    }

    func refreshAll() {
        for c in controllers {
            if let cfg = store.mask(c.config.id) {
                c.config = cfg
            }
            c.applyAll()
        }
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
        restartDetectTimer()
    }

    // MARK: 状态栏

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled",
                              accessibilityDescription: "影幕")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = store.settings

        let headerText = controllers.isEmpty
            ? "影幕 — 没有遮挡条，按 \(s.hotkey(.newMask).display) 新建"
            : "影幕 — \(controllers.count) 条遮挡"
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        add(menu, "新建遮挡条", #selector(menuAddMask), hint: s.hotkey(.newMask).display)
        if lastClosed != nil {
            add(menu, "撤销关闭", #selector(menuUndoClose))
        }
        let anyVisible = controllers.contains { !$0.config.hidden }
        add(menu, anyVisible ? "全部隐藏" : "全部显示", #selector(menuToggleHidden), hint: s.hotkey(.toggleHidden).display)
        let anyUnlocked = controllers.contains { !$0.config.locked }
        add(menu, anyUnlocked ? "全部锁定（鼠标穿透）" : "全部解锁", #selector(menuToggleLock), hint: s.hotkey(.toggleLock).display)
        add(menu, s.peekHold ? "偷看：按住 \(s.hotkey(.peek).display)" : "偷看：按 \(s.hotkey(.peek).display) 切换",
            #selector(menuPeekOnce))

        menu.addItem(.separator())

        if let active = activeController {
            let t = NSMenuItem(title: "当前：\(active.config.label)", action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)

            let skinItem = NSMenuItem(title: "皮肤", action: nil, keyEquivalent: "")
            skinItem.submenu = skinMenu(for: active)
            menu.addItem(skinItem)

            let trackItem = NSMenuItem(title: "追踪", action: nil, keyEquivalent: "")
            trackItem.submenu = trackMenu(for: active)
            menu.addItem(trackItem)

            let opacityItem = NSMenuItem(title: "不透明度 \(Int(active.config.opacity * 100))%", action: nil, keyEquivalent: "")
            opacityItem.submenu = opacityMenu(for: active)
            menu.addItem(opacityItem)

            add(menu, "摆回屏幕中下方", #selector(menuResetPos))

            if controllers.count > 1 {
                let pick = NSMenuItem(title: "切换到", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for (i, c) in controllers.enumerated() {
                    let it = NSMenuItem(title: "\(i + 1). \(c.config.label)", action: #selector(menuPickMask(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = c.config.id
                    it.state = c === active ? .on : .off
                    sub.addItem(it)
                }
                pick.submenu = sub
                menu.addItem(pick)
            }
        }

        menu.addItem(.separator())
        add(menu, "设置…", #selector(menuSettings), hint: "⌘,")
        add(menu, "退出影幕", #selector(menuQuit), hint: "⌘Q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, hint: String? = nil) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        if let hint {
            item.attributedTitle = menuTitle(title, hint: hint)
        }
        menu.addItem(item)
    }

    private func menuTitle(_ title: String, hint: String) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)])
        s.append(NSAttributedString(
            string: "   " + hint,
            attributes: [.font: NSFont.menuFont(ofSize: 0),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        return s
    }

    func skinMenu(for c: MaskController) -> NSMenu {
        let m = NSMenu()
        for skin in store.skins {
            let it = NSMenuItem(title: skin.name, action: #selector(menuPickSkin(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [c.config.id, skin.id]
            it.state = skin.id == c.config.skinID ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let edit = NSMenuItem(title: "编辑皮肤…", action: #selector(menuSettings), keyEquivalent: "")
        edit.target = self
        m.addItem(edit)
        return m
    }

    func trackMenu(for c: MaskController) -> NSMenu {
        let m = NSMenu()
        let manual = NSMenuItem(title: TrackMode.manual.label, action: #selector(menuTrackManual(_:)), keyEquivalent: "")
        manual.target = self
        manual.representedObject = c.config.id
        manual.state = c.config.trackMode == .manual ? .on : .off
        m.addItem(manual)

        let winItem = NSMenuItem(title: TrackMode.window.label, action: nil, keyEquivalent: "")
        winItem.state = c.config.trackMode == .window ? .on : .off
        let sub = NSMenu()
        let own = Set([ProcessInfo.processInfo.processIdentifier])
        let wins = WindowTracker.list(excluding: own)
        if wins.isEmpty {
            let empty = NSMenuItem(title: "没找到可跟随的窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        for w in wins.prefix(18) {
            let it = NSMenuItem(title: w.display, action: #selector(menuTrackWindow(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [c.config.id, w.id, w.owner] as [Any]
            it.state = (c.config.trackMode == .window && c.config.trackWindowID == w.id) ? .on : .off
            sub.addItem(it)
        }
        winItem.submenu = sub
        m.addItem(winItem)

        let auto = NSMenuItem(title: TrackMode.subtitle.label + "（需屏幕录制权限）",
                              action: #selector(menuTrackSubtitle(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = c.config.id
        auto.state = c.config.trackMode == .subtitle ? .on : .off
        m.addItem(auto)
        return m
    }

    func opacityMenu(for c: MaskController) -> NSMenu {
        let m = NSMenu()
        for v in [1.0, 0.95, 0.85, 0.7, 0.55, 0.4, 0.25] {
            let it = NSMenuItem(title: "\(Int(v * 100))%", action: #selector(menuPickOpacity(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [c.config.id, v] as [Any]
            it.state = abs(c.config.opacity - v) < 0.02 ? .on : .off
            m.addItem(it)
        }
        return m
    }

    // MARK: 菜单动作

    @objc private func menuAddMask() { addMask() }

    @objc private func menuUndoClose() { undoClose() }

    @objc private func menuResetPos() {
        if let c = activeController { resetPosition(c) }
    }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleHidden() { toggleHidden() }
    @objc private func menuToggleLock() { toggleLock() }

    @objc private func menuPeekOnce() {
        if store.settings.peekHold {
            setPeek(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.setPeek(false) }
        } else {
            setPeek(!peeking)
        }
    }

    @objc private func menuPickMask(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { store.activeMaskID = id }
    }

    @objc private func menuPickSkin(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [UUID], arr.count == 2,
              let c = controller(arr[0]) else { return }
        c.setSkin(arr[1])
    }

    @objc private func menuPickOpacity(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [Any], arr.count == 2,
              let id = arr[0] as? UUID, let v = arr[1] as? Double,
              let c = controller(id) else { return }
        c.setOpacity(v)
    }

    @objc private func menuTrackManual(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let c = controller(id) else { return }
        c.setTrackMode(.manual)
        restartDetectTimer()
    }

    @objc private func menuTrackWindow(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [Any], arr.count == 3,
              let id = arr[0] as? UUID, let wid = arr[1] as? UInt32, let owner = arr[2] as? String,
              let c = controller(id) else { return }
        c.setTrackMode(.window, windowID: wid, owner: owner)
        restartDetectTimer()
    }

    @objc private func menuTrackSubtitle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let c = controller(id) else { return }
        c.setTrackMode(.subtitle)
        restartDetectTimer()
    }

    // MARK: 工具条 / 右键

    func handleToolClick(_ item: ToolItem, on c: MaskController) {
        switch item {
        case .lock:
            c.setLocked(!c.config.locked)
        case .track:
            popUp(trackMenu(for: c))
        case .skin:
            popUp(skinMenu(for: c))
        case .settings:
            openSettings()
        case .close:
            removeMask(c)
        }
    }

    private func popUp(_ menu: NSMenu) {
        let p = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: p.x, y: p.y), in: nil)
    }

    func showContextMenu(for c: MaskController, at screenPoint: NSPoint) {
        let m = NSMenu()

        let lock = NSMenuItem(title: c.config.locked ? "解锁" : "锁定（鼠标穿透）",
                              action: #selector(ctxLock(_:)), keyEquivalent: "")
        lock.target = self
        lock.representedObject = c.config.id
        m.addItem(lock)

        let hide = NSMenuItem(title: "隐藏这条", action: #selector(ctxHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = c.config.id
        m.addItem(hide)

        m.addItem(.separator())

        let skin = NSMenuItem(title: "皮肤", action: nil, keyEquivalent: "")
        skin.submenu = skinMenu(for: c)
        m.addItem(skin)

        let track = NSMenuItem(title: "追踪", action: nil, keyEquivalent: "")
        track.submenu = trackMenu(for: c)
        m.addItem(track)

        let op = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        op.submenu = opacityMenu(for: c)
        m.addItem(op)

        m.addItem(.separator())

        let reset = NSMenuItem(title: "摆回屏幕中下方", action: #selector(ctxReset(_:)), keyEquivalent: "")
        reset.target = self
        reset.representedObject = c.config.id
        m.addItem(reset)

        let dup = NSMenuItem(title: "复制一条", action: #selector(menuAddMask), keyEquivalent: "")
        dup.target = self
        m.addItem(dup)

        let del = NSMenuItem(title: "移除这条", action: #selector(ctxRemove(_:)), keyEquivalent: "")
        del.target = self
        del.representedObject = c.config.id
        m.addItem(del)

        m.addItem(.separator())
        let set = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: "")
        set.target = self
        m.addItem(set)

        m.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    @objc private func ctxLock(_ s: NSMenuItem) {
        guard let id = s.representedObject as? UUID, let c = controller(id) else { return }
        c.setLocked(!c.config.locked)
    }

    @objc private func ctxHide(_ s: NSMenuItem) {
        guard let id = s.representedObject as? UUID, let c = controller(id) else { return }
        c.setHidden(true)
    }

    @objc private func ctxReset(_ s: NSMenuItem) {
        guard let id = s.representedObject as? UUID, let c = controller(id) else { return }
        resetPosition(c)
    }

    @objc private func ctxRemove(_ s: NSMenuItem) {
        guard let id = s.representedObject as? UUID, let c = controller(id) else { return }
        removeMask(c)
    }

    // MARK: 全局动作

    func setPeek(_ on: Bool) {
        peeking = on
        for c in controllers { c.setPeek(on) }
    }

    func toggleHidden() {
        let anyVisible = controllers.contains { !$0.config.hidden }
        for c in controllers { c.setHidden(anyVisible) }
    }

    func toggleLock() {
        let anyUnlocked = controllers.contains { !$0.config.locked }
        for c in controllers { c.setLocked(anyUnlocked) }
    }

    func cycleSkin() {
        guard let c = activeController, !store.skins.isEmpty else { return }
        let i = store.skins.firstIndex { $0.id == c.config.skinID } ?? -1
        let next = store.skins[(i + 1) % store.skins.count]
        c.setSkin(next.id)
    }

    // MARK: 快捷键

    func registerHotkeys() {
        let hk = HotkeyManager.shared
        hk.onDown = { [weak self] action in
            guard let self else { return }
            switch action {
            case .peek:
                if self.store.settings.peekHold { self.setPeek(true) }
                else { self.setPeek(!self.peeking) }
            case .toggleHidden: self.toggleHidden()
            case .toggleLock: self.toggleLock()
            case .newMask: self.addMask()
            case .cycleSkin: self.cycleSkin()
            }
        }
        hk.onUp = { [weak self] action in
            guard let self, action == .peek, self.store.settings.peekHold else { return }
            self.setPeek(false)
        }
        hk.register(store.settings.hotkeyMap, enabled: store.settings.hotkeysEnabled)
    }

    // MARK: 定时器

    private func startTimers() {
        followTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for c in self.controllers { c.tickWindowFollow() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        followTimer = t
        restartDetectTimer()
    }

    func restartDetectTimer() {
        detectTimer?.invalidate()
        detectTimer = nil
        let needed = controllers.contains { $0.config.trackMode == .subtitle && !$0.config.hidden }
        guard needed else { return }
        detector.invalidate()
        let hz = max(0.5, min(8, store.settings.detectRateHz))
        let t = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runDetection()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        detectTimer = t
    }

    private func runDetection() {
        let targets = controllers.filter { $0.config.trackMode == .subtitle && !$0.config.hidden }
        guard !targets.isEmpty else { return }
        let own = Set(controllers.map { $0.windowNumber })
        let sensitivity = store.settings.detectSensitivity
        Task { @MainActor in
            for c in targets {
                do {
                    if let range = try await detector.detect(band: c.searchBand(),
                                                             excluding: own,
                                                             sensitivity: sensitivity) {
                        c.applyDetected(range: range)
                        c.noteDetect(success: true)
                    } else {
                        c.noteDetect(success: false)
                    }
                } catch SubtitleDetector.DetectError.noPermission {
                    self.handleNoScreenPermission()
                    return
                } catch {
                    c.noteDetect(success: false)
                }
            }
        }
    }

    private func handleNoScreenPermission() {
        detectTimer?.invalidate()
        detectTimer = nil
        for c in controllers where c.config.trackMode == .subtitle {
            c.setTrackMode(.manual)
        }
        guard !permissionAlertShown else { return }
        permissionAlertShown = true
        let a = NSAlert()
        a.messageText = "自动吸附字幕需要屏幕录制权限"
        a.informativeText = "影幕要采样字幕区域才能找到字幕行的位置。到「系统设置 — 隐私与安全性 — 屏幕录制」里勾上影幕，然后重新打开一次这个 App。\n\n在这之前，追踪已经切回手动摆放。"
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        permissionAlertShown = false
    }

    // MARK: 设置窗

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "影幕 設定"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.063, alpha: 1)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 780, height: 560)
            let root = SettingsView(app: self).environmentObject(store)
            w.contentView = NSHostingView(rootView: root)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showWelcome() {
        let s = store.settings
        let a = NSAlert()
        a.messageText = "影幕已经在屏幕上了"
        a.informativeText = """
        默认那条毛玻璃摆在画面下方三分之一处，直接拖到字幕上就能用。

        拖条身移动，拖边缘缩放，鼠标移上去出工具条。
        \(s.hotkey(.peek).display)　按住偷看一眼字幕
        \(s.hotkey(.toggleHidden).display)　收起 / 放出
        \(s.hotkey(.toggleLock).display)　锁定后鼠标穿透，点得到播放器
        \(s.hotkey(.newMask).display)　再加一条（双语字幕各遮各的）

        右键遮挡条，或点菜单栏图标，可以换皮肤和追踪模式。
        """
        a.addButton(withTitle: "开始")
        a.addButton(withTitle: "打开设置")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn { openSettings() }
    }
}
