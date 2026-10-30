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

        // kagemaku settings [页面] 会带着 --settings 启动或转发过来
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings") {
            let pane = args.count > i + 1 ? SettingsPane(rawValue: args[i + 1]) : nil
            DispatchQueue.main.async { [weak self] in self?.openSettings(pane: pane) }
            UserDefaults.standard.set(true, forKey: "kagemaku.welcomed")
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.shinkouniv.kagemaku.openSettings" + (Store.testDataDir == nil ? "" : ".test")),
            object: nil, queue: .main
        ) { [weak self] note in
            let pane = (note.object as? String).flatMap(SettingsPane.init(rawValue:))
            MainActor.assumeIsolated { self?.openSettings(pane: pane) }
        }

        if Store.testDataDir != nil, ProcessInfo.processInfo.environment["KAGEMAKU_TEST_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // 测试截图：启动后直接弹出第一条的右键菜单
        if Store.testDataDir != nil, ProcessInfo.processInfo.environment["KAGEMAKU_TEST_MENU"] == "1",
           let c = controllers.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                let f = c.visualFrame
                self?.showContextMenu(for: c, at: NSPoint(x: f.midX, y: f.maxY))
            }
        }

        if Store.testDataDir == nil && !UserDefaults.standard.bool(forKey: "kagemaku.welcomed") {
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
            m.frame = last.visualFrame.offsetBy(dx: 26, dy: -26)
            m.skinID = last.config.skinID
            m.opacity = last.config.opacity
        }
        m.label = "遮挡条 \(store.masks.count + 1)"
        store.masks.append(m)
        store.save()
        let c = MaskController(config: m, app: self)
        controllers.append(c)
        store.activeMaskID = m.id
        rescueOffscreen()
    }

    /// 移除要先问一句；之后还能从菜单栏撤销一次
    func confirmRemove(_ c: MaskController) {
        let a = NSAlert()
        a.messageText = "移除「\(c.config.label)」？"
        a.informativeText = "位置、用途、皮肤和部件会一起删掉。删完可以在菜单栏里点「撤销移除」放回来，只能撤销最近一次。\n\n只是暂时不想看见的话，用「隐藏」就行。"
        let ok = a.addButton(withTitle: "移除")
        ok.hasDestructiveAction = true
        a.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if withPanelsLowered({ a.runModal() }) == .alertFirstButtonReturn { removeMask(c) }
    }

    func removeMask(_ c: MaskController) {
        lastClosed = c.config
        c.close()
        controllers.removeAll { $0 === c }
        store.masks.removeAll { $0.id == c.config.id }
        store.activeMaskID = store.masks.first?.id
        store.save()
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
        restartDetectTimer()
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
        restartDetectTimer()
    }

    /// 只刷视觉，不动窗口位置和定时器（拖滑块时用）
    func refreshVisuals() {
        for c in controllers {
            if let cfg = store.mask(c.config.id) { c.config.merge(visualsFrom: cfg) }
            c.applyAll()
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
            if let cfg = store.mask(c.config.id) { c.config.merge(visualsFrom: cfg) }
            c.applyAll()
        }
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
        restartDetectTimer()
    }

    // MARK: 弹出菜单和对话框时让路

    /// 遮挡条在屏保那一层，比弹出菜单和对话框都高。右键菜单从鼠标位置弹出，
    /// 上面几项正好压在条身底下，隔着毛玻璃看就是一片灰、点不到。弹出期间先把条降到普通浮动层。
    private var lowered = 0
    var panelsLowered: Bool { lowered > 0 }

    func lowerPanels() {
        lowered += 1
        for c in controllers { c.panel.level = .floating }
    }

    func restorePanels() {
        lowered = max(0, lowered - 1)
        guard lowered == 0 else { return }
        let level: NSWindow.Level = store.settings.aboveFullscreen ? .screenSaver : .floating
        for c in controllers { c.panel.level = level }
    }

    func withPanelsLowered<T>(_ body: () -> T) -> T {
        lowerPanels()
        defer { restorePanels() }
        return body()
    }

    func menuWillOpen(_ menu: NSMenu) { lowerPanels() }
    func menuDidClose(_ menu: NSMenu) { restorePanels() }

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

        let hiddenCount = controllers.filter { $0.config.hidden }.count
        let headerText: String
        if controllers.isEmpty {
            headerText = "没有遮挡条，按 \(s.hotkey(.newMask).display) 新建"
        } else if hiddenCount > 0 {
            headerText = "\(controllers.count) 条遮挡条，\(hiddenCount) 条藏着"
        } else {
            headerText = "\(controllers.count) 条遮挡条"
        }
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        add(menu, "新建遮挡条", #selector(menuAddMask), hint: s.hotkey(.newMask).display)
        if lastClosed != nil {
            add(menu, "撤销移除", #selector(menuUndoClose))
        }
        if !controllers.isEmpty {
            let anyVisible = controllers.contains { !$0.config.hidden }
            add(menu, anyVisible ? "全部隐藏" : "全部显示", #selector(menuToggleHidden), hint: s.hotkey(.toggleHidden).display)
            let anyUnlocked = controllers.contains { !$0.config.locked }
            add(menu, anyUnlocked ? "全部锁定（鼠标穿透）" : "全部解锁", #selector(menuToggleLock), hint: s.hotkey(.toggleLock).display)
            add(menu, s.peekHold ? "偷看：按住 \(s.hotkey(.peek).display)" : "偷看：按 \(s.hotkey(.peek).display) 切换",
                #selector(menuPeekOnce))
        }

        if let active = activeController {
            menu.addItem(.separator())
            let t = NSMenuItem(title: controllers.count > 1 ? "当前：\(active.config.label)" : active.config.label,
                               action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)
            for item in barItems(for: active) { menu.addItem(item) }

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
        add(menu, "设置…", #selector(menuSettings))
        add(menu, "退出影幕", #selector(menuQuit))
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

    private func item(_ title: String, _ sel: Selector, _ c: MaskController, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.representedObject = c.config.id
        it.state = on ? .on : .off
        return it
    }

    /// 针对一条遮挡条的那几项，菜单栏和右键共用
    private func barItems(for c: MaskController) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        let mode = NSMenuItem(title: "用途", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for m in MaskMode.allCases {
            let it = item("\(m.label)：\(m.note)", #selector(menuPickMode(_:)), c, on: c.config.mode == m)
            it.tag = m.rawValue
            modeMenu.addItem(it)
        }
        mode.submenu = modeMenu
        out.append(mode)

        let track = NSMenuItem(title: "追踪", action: nil, keyEquivalent: "")
        track.submenu = trackMenu(for: c)
        out.append(track)

        if c.config.mode == .cover {
            let skin = NSMenuItem(title: "皮肤", action: nil, keyEquivalent: "")
            skin.submenu = skinMenu(for: c)
            out.append(skin)
            let op = NSMenuItem(title: "不透明度 \(Int(c.config.opacity * 100))%", action: nil, keyEquivalent: "")
            op.submenu = opacityMenu(for: c)
            out.append(op)
        }
        out.append(item("摆回屏幕中下方", #selector(ctxReset(_:)), c))
        return out
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
        let edit = NSMenuItem(title: "编辑皮肤…", action: #selector(menuSkinSettings), keyEquivalent: "")
        edit.target = self
        m.addItem(edit)
        return m
    }

    func trackMenu(for c: MaskController) -> NSMenu {
        let m = NSMenu()
        let auto = NSMenuItem(title: c.config.mode == .learn ? "自动对齐中文行（要屏幕录制权限）" : "自动对齐字幕（要屏幕录制权限）",
                              action: #selector(menuTrackSubtitle(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = c.config.id
        auto.state = c.config.trackMode == .subtitle ? .on : .off
        m.addItem(auto)

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

    @objc private func menuSettings() { openSettings() }
    @objc private func menuSkinSettings() { openSettings(pane: .skins) }
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

    @objc private func menuPickMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let c = controller(id),
              let mode = MaskMode(rawValue: sender.tag) else { return }
        c.setMode(mode)
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
        case .learn:
            c.setMode(c.config.mode == .learn ? .cover : .learn)
        case .track:
            popUp(trackMenu(for: c))
        case .skin:
            popUp(skinMenu(for: c))
        case .settings:
            openSettings(pane: .masks)
        case .hide:
            c.setHidden(true)
        }
    }

    private func popUp(_ menu: NSMenu) {
        let p = NSEvent.mouseLocation
        withPanelsLowered { _ = menu.popUp(positioning: nil, at: NSPoint(x: p.x, y: p.y), in: nil) }
    }

    func showContextMenu(for c: MaskController, at screenPoint: NSPoint) {
        let m = NSMenu()
        m.autoenablesItems = false

        let learn = item("学外语：只盖中文", #selector(ctxToggleLearn(_:)), c, on: c.config.mode == .learn)
        m.addItem(learn)
        m.addItem(item(c.config.locked ? "解锁" : "锁定（鼠标穿透）", #selector(ctxLock(_:)), c))
        m.addItem(item("隐藏这条", #selector(ctxHide(_:)), c))

        m.addItem(.separator())
        let track = NSMenuItem(title: "追踪", action: nil, keyEquivalent: "")
        track.submenu = trackMenu(for: c)
        m.addItem(track)
        if c.config.mode == .cover {
            let skin = NSMenuItem(title: "皮肤", action: nil, keyEquivalent: "")
            skin.submenu = skinMenu(for: c)
            m.addItem(skin)
            let op = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
            op.submenu = opacityMenu(for: c)
            m.addItem(op)
        }

        m.addItem(.separator())
        m.addItem(item("摆回屏幕中下方", #selector(ctxReset(_:)), c))
        let more = NSMenuItem(title: "再加一条", action: #selector(menuAddMask), keyEquivalent: "")
        more.target = self
        m.addItem(more)
        m.addItem(item("移除这条…", #selector(ctxRemove(_:)), c))

        m.addItem(.separator())
        let set = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: "")
        set.target = self
        m.addItem(set)
        let quit = NSMenuItem(title: "退出影幕", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        m.addItem(quit)

        withPanelsLowered { _ = m.popUp(positioning: nil, at: screenPoint, in: nil) }
    }

    @objc private func ctxToggleLearn(_ s: NSMenuItem) {
        guard let id = s.representedObject as? UUID, let c = controller(id) else { return }
        c.setMode(c.config.mode == .learn ? .cover : .learn)
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
        confirmRemove(c)
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
        guard let c = activeController, c.config.mode == .cover, !store.skins.isEmpty else { return }
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
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                for c in self.controllers {
                    c.tickMouse()
                    if self.tick % 2 == 0 { c.tickWindowFollow() }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        followTimer = t
        restartDetectTimer()
    }
    private var tick = 0

    func restartDetectTimer() {
        detectTimer?.invalidate()
        detectTimer = nil
        let targets = controllers.filter { $0.wantsDetection }
        guard !targets.isEmpty else { return }
        detector.invalidate()
        if !SubtitleDetector.hasPermission {
            askScreenPermission()
        } else if !detector.warmedUp {
            for c in targets { c.warming = true; c.refreshTitle() }
        }
        let hz = max(0.5, min(4, store.settings.detectRateHz))
        let t = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runDetection()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        detectTimer = t
        runDetection()
    }

    private var detecting = false

    private func runDetection() {
        let targets = controllers.filter { $0.wantsDetection && !$0.isDragging }
        guard !targets.isEmpty, !detecting else { return }
        // 没授权就不拍，等用户在系统设置里勾上再重开
        guard SubtitleDetector.hasPermission else { return }
        detecting = true
        let own = Set(controllers.map { $0.windowNumber })
        Task { @MainActor in
            defer { self.detecting = false }
            for c in targets {
                do {
                    if let lines = try await detector.read(band: c.searchBand(), excluding: own) {
                        c.applyReading(lines)
                    }
                } catch SubtitleDetector.DetectError.noPermission {
                    self.askScreenPermission()
                    return
                } catch {
                    c.noteDetect(success: false)
                }
            }
        }
    }

    /// 只在这次启动里提醒一次。授权之后系统会要求重开影幕，重开就能用了
    private func askScreenPermission() {
        for c in controllers where c.wantsDetection {
            c.model.trackTitle = "要屏幕录制权限才能认字幕"
        }
        guard !permissionAlertShown else { return }
        permissionAlertShown = true
        CGRequestScreenCaptureAccess()
        let a = NSAlert()
        a.messageText = "认字幕要屏幕录制权限"
        a.informativeText = "影幕只拍遮挡条附近那一小块画面，在本机认出哪一行是字幕、哪一行是中文，然后把玻璃挪过去。画面不存、不上传。\n\n到「系统设置 › 隐私与安全性 › 屏幕录制」里打开影幕，系统会提示重开一次。\n\n没授权的时候，玻璃照样能用，只是要自己拖到字幕上。"
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "以后再说")
        NSApp.activate(ignoringOtherApps: true)
        if withPanelsLowered({ a.runModal() }) == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 设置窗

    func openSettings(pane: SettingsPane? = nil) {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "影幕 设置"
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 520)
            w.contentView = NSHostingView(rootView: SettingsView(app: self, nav: settingsNav).environmentObject(store))
            w.center()
            w.setFrameAutosaveName("KagemakuSettings")
            settingsWindow = w
        }
        if let pane { settingsNav.pane = pane }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    let settingsNav = SettingsNav()

    private func showWelcome() {
        let s = store.settings
        let a = NSAlert()
        a.messageText = "影幕已经在屏幕上了"
        a.informativeText = """
        屏幕下方那条玻璃，拖到字幕上就能用。

        练听力：整条挡住，听不出来按住 \(s.hotkey(.peek).display) 偷看一眼。
        学外语：右键选「学外语：只盖中文」，玻璃变成透明的，只糊掉中文那一行，外文照常看。

        拖条身移动，拖边缘缩放，鼠标停上去出工具条。
        \(s.hotkey(.toggleHidden).display)　藏起来 / 放出来
        \(s.hotkey(.toggleLock).display)　锁定后鼠标穿透，点得到播放器
        右键遮挡条有完整菜单，也能从那里退出。
        """
        a.addButton(withTitle: "开始")
        a.addButton(withTitle: "打开设置")
        NSApp.activate(ignoringOtherApps: true)
        if withPanelsLowered({ a.runModal() }) == .alertSecondButtonReturn { openSettings() }
    }
}

extension MaskConfig {
    /// 从存档里拿设置项，位置留用控制器手上的：跟随窗口、自动对齐时位置一直在变，存档里的是旧的
    mutating func merge(visualsFrom other: MaskConfig) {
        let f = frame
        self = other
        frame = f
    }
}
