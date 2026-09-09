import AppKit
import SwiftUI
import Carbon.HIToolbox

struct HotkeySpec: Codable, Equatable {
    var key: UInt32
    var mods: UInt32   // Carbon: cmdKey / optionKey / controlKey / shiftKey

    static let cmd = UInt32(cmdKey)
    static let opt = UInt32(optionKey)
    static let ctrl = UInt32(controlKey)
    static let shift = UInt32(shiftKey)

    var display: String {
        var s = ""
        if mods & Self.ctrl != 0 { s += "⌃" }
        if mods & Self.opt != 0 { s += "⌥" }
        if mods & Self.shift != 0 { s += "⇧" }
        if mods & Self.cmd != 0 { s += "⌘" }
        s += HotkeySpec.keyName(key)
        return s
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"
        ]
        return map[code] ?? "键\(code)"
    }

    static func fromEvent(_ e: NSEvent) -> HotkeySpec? {
        var m: UInt32 = 0
        if e.modifierFlags.contains(.command) { m |= cmd }
        if e.modifierFlags.contains(.option) { m |= opt }
        if e.modifierFlags.contains(.control) { m |= ctrl }
        if e.modifierFlags.contains(.shift) { m |= shift }
        guard m != 0 else { return nil }
        return HotkeySpec(key: UInt32(e.keyCode), mods: m)
    }
}

enum HotkeyAction: String, CaseIterable, Codable {
    case peek, toggleHidden, toggleLock, newMask, cycleSkin

    var label: String {
        switch self {
        case .peek: return "偷看字幕"
        case .toggleHidden: return "显示 / 隐藏遮挡条"
        case .toggleLock: return "锁定 / 解锁"
        case .newMask: return "新建一条遮挡条"
        case .cycleSkin: return "换下一个皮肤"
        }
    }

    var note: String {
        switch self {
        case .peek: return "按住时遮挡条变透明，松开复原（可在设置里改成按一下切换）"
        case .toggleHidden: return "整块收起来，不占画面"
        case .toggleLock: return "锁定后鼠标穿透，点得到底下的播放器"
        case .newMask: return "双语字幕就摆两条，各遮各的"
        case .cycleSkin: return "在皮肤列表里往后翻一个"
        }
    }

    static let defaults: [HotkeyAction: HotkeySpec] = [
        .peek: HotkeySpec(key: 14, mods: HotkeySpec.opt | HotkeySpec.cmd),          // ⌥⌘E
        .toggleHidden: HotkeySpec(key: 46, mods: HotkeySpec.opt | HotkeySpec.cmd),  // ⌥⌘M
        .toggleLock: HotkeySpec(key: 37, mods: HotkeySpec.opt | HotkeySpec.cmd),    // ⌥⌘L
        .newMask: HotkeySpec(key: 45, mods: HotkeySpec.opt | HotkeySpec.cmd),       // ⌥⌘N
        .cycleSkin: HotkeySpec(key: 40, mods: HotkeySpec.opt | HotkeySpec.cmd),     // ⌥⌘K
    ]
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: HotkeyAction] = [:]
    private var handler: EventHandlerRef?

    var onDown: ((HotkeyAction) -> Void)?
    var onUp: ((HotkeyAction) -> Void)?

    private init() {}

    func install() {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                HotkeyManager.shared.dispatch(id: hkID.id, pressed: pressed)
            }
            return noErr
        }, 2, &specs, nil, &handler)
    }

    private func dispatch(id: UInt32, pressed: Bool) {
        guard let action = actions[id] else { return }
        if pressed { onDown?(action) } else { onUp?(action) }
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    func register(_ map: [HotkeyAction: HotkeySpec], enabled: Bool) {
        unregisterAll()
        guard enabled else { return }
        install()
        for (i, action) in HotkeyAction.allCases.enumerated() {
            guard let spec = map[action] else { continue }
            let id = UInt32(i + 1)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x4B474D4B), id: id)  // 'KGMK'
            let status = RegisterEventHotKey(spec.key, spec.mods, hkID,
                                             GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[id] = ref
                actions[id] = action
            }
        }
    }
}

// MARK: - 设置里的快捷键录制框

struct KeyRecorder: NSViewRepresentable {
    @Binding var spec: HotkeySpec
    var onChange: (HotkeySpec) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.spec = spec
        v.onChange = { s in
            self.spec = s
            self.onChange(s)
        }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.spec = spec
        v.needsDisplay = true
    }

    final class RecorderView: NSView {
        var spec = HotkeySpec(key: 0, mods: 0) { didSet { needsDisplay = true } }
        var onChange: ((HotkeySpec) -> Void)?
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 118, height: 26) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { recording = false; return }
            if let s = HotkeySpec.fromEvent(event) {
                spec = s
                recording = false
                onChange?(s)
            } else {
                NSSound.beep()
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let r = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                       : NSColor.white.withAlphaComponent(0.06)).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor
                       : NSColor.white.withAlphaComponent(0.18)).setStroke()
            path.lineWidth = 1
            path.stroke()

            let text = recording ? "按下组合键…" : spec.display
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(recording ? 0.9 : 0.82),
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                                y: (bounds.height - size.height) / 2),
                                    withAttributes: attrs)
        }
    }
}
