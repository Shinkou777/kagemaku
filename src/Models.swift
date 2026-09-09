import AppKit
import SwiftUI

// MARK: - 颜色

struct RGBA: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: String, alpha: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 8 {
            self.init(Double((v >> 24) & 0xFF) / 255,
                      Double((v >> 16) & 0xFF) / 255,
                      Double((v >> 8) & 0xFF) / 255,
                      Double(v & 0xFF) / 255)
        } else {
            self.init(Double((v >> 16) & 0xFF) / 255,
                      Double((v >> 8) & 0xFF) / 255,
                      Double(v & 0xFF) / 255,
                      alpha)
        }
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    static func from(_ color: Color) -> RGBA {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return RGBA(Double(ns.redComponent), Double(ns.greenComponent),
                    Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

// MARK: - 毛玻璃材质

enum MaterialKind: String, Codable, CaseIterable, Identifiable {
    case hud, popover, menu, sidebar, underWindow, fullScreenUI, sheet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hud: return "HUD（最通透）"
        case .popover: return "ポップオーバー"
        case .menu: return "メニュー"
        case .sidebar: return "サイドバー"
        case .underWindow: return "厚玻璃"
        case .fullScreenUI: return "全屏 UI"
        case .sheet: return "シート"
        }
    }

    /// 设置页预览用：真机上的玻璃走 AppKit，这里只是模拟观感
    @ViewBuilder
    var previewMaterial: some View {
        switch self {
        case .hud, .popover: Rectangle().fill(.ultraThinMaterial)
        case .menu, .sidebar: Rectangle().fill(.thinMaterial)
        case .fullScreenUI: Rectangle().fill(.regularMaterial)
        case .underWindow, .sheet: Rectangle().fill(.thickMaterial)
        }
    }

    var material: NSVisualEffectView.Material {
        switch self {
        case .hud: return .hudWindow
        case .popover: return .popover
        case .menu: return .menu
        case .sidebar: return .sidebar
        case .underWindow: return .underWindowBackground
        case .fullScreenUI: return .fullScreenUI
        case .sheet: return .sheet
        }
    }
}

enum AppearanceKind: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮"
        case .dark: return "暗"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .vibrantLight)
        case .dark: return NSAppearance(named: .vibrantDark)
        }
    }
}

// MARK: - 动态效果

enum SkinEffect: String, Codable, CaseIterable, Identifiable {
    case none, shimmer, scanline, aurora, pulse, grain, frost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "无"
        case .shimmer: return "流光扫过"
        case .scanline: return "CRT 扫描线"
        case .aurora: return "极光流动"
        case .pulse: return "边框呼吸"
        case .grain: return "颗粒噪点"
        case .frost: return "霜面增色"
        }
    }

    var animated: Bool {
        switch self {
        case .none, .grain, .frost: return false
        default: return true
        }
    }
}

// MARK: - 皮肤

struct Skin: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "新皮肤"
    var builtIn: Bool = false

    var blur: Bool = true
    var material: MaterialKind = .hud
    var appearance: AppearanceKind = .dark
    var blurSaturation: Double = 1.0

    var tintTop: RGBA = RGBA(hex: "#FFFFFF", alpha: 0.06)
    var tintBottom: RGBA = RGBA(hex: "#FFFFFF", alpha: 0.0)
    var gradientAngle: Double = 90

    var cornerRadius: Double = 16
    var borderWidth: Double = 1
    var borderTop: RGBA = RGBA(hex: "#FFFFFF", alpha: 0.32)
    var borderBottom: RGBA = RGBA(hex: "#FFFFFF", alpha: 0.08)

    var glowRadius: Double = 18
    var glowColor: RGBA = RGBA(hex: "#000000", alpha: 0.45)

    var effect: SkinEffect = .shimmer
    var effectColor: RGBA = RGBA(hex: "#FFFFFF", alpha: 0.5)
    var effectIntensity: Double = 0.35
    var effectSpeed: Double = 1.0

    var innerHighlight: Double = 0.35

    /// 条被拉扁时圆角要跟着收，不然玻璃遮罩会被拉变形
    static func clampRadius(_ r: Double, _ size: CGSize) -> CGFloat {
        let limit = min(size.width, size.height) / 2
        return max(0, min(CGFloat(r), limit))
    }
}

// MARK: - 遮挡条

enum TrackMode: Int, Codable, CaseIterable, Identifiable {
    case manual = 0
    case window = 1
    case subtitle = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: return "手动摆放"
        case .window: return "跟随播放器窗口"
        case .subtitle: return "自动吸附字幕行"
        }
    }

    var symbol: String {
        switch self {
        case .manual: return "hand.draw"
        case .window: return "macwindow.on.rectangle"
        case .subtitle: return "scope"
        }
    }
}

struct MaskConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String = "遮挡条"
    var frame: CGRect = CGRect(x: 400, y: 160, width: 900, height: 96)
    var skinID: UUID = UUID()
    var opacity: Double = 0.95
    var locked: Bool = false
    var hidden: Bool = false

    var trackMode: TrackMode = .manual
    var trackWindowID: UInt32? = nil
    var trackWindowOwner: String? = nil
    // 相对于被跟随窗口的归一化锚点
    var anchorX: Double = 0.1
    var anchorY: Double = 0.78
    var anchorW: Double = 0.8
    var anchorH: Double = 0.12

    /// 条身上叠的显示部件
    var widgets: [MaskWidget] = MaskWidget.defaultSet
}

// MARK: - 全局设置

struct GlobalSettings: Codable {
    var peekOpacity: Double = 0.05
    var peekHold: Bool = true          // true 按住透视，false 按一下切换
    var detectSensitivity: Double = 0.45
    var detectBand: Double = 150
    var detectRateHz: Double = 3
    var detectPadding: Double = 14
    var reduceMotion: Bool = false
    var hotkeysEnabled: Bool = true
    var snapEdges: Bool = true
    var aboveFullscreen: Bool = true
    var hotkeys: [String: HotkeySpec] = GlobalSettings.defaultHotkeys

    static var defaultHotkeys: [String: HotkeySpec] {
        var d: [String: HotkeySpec] = [:]
        for (k, v) in HotkeyAction.defaults { d[k.rawValue] = v }
        return d
    }

    func hotkey(_ a: HotkeyAction) -> HotkeySpec {
        hotkeys[a.rawValue] ?? HotkeyAction.defaults[a] ?? HotkeySpec(key: 0, mods: 0)
    }

    var hotkeyMap: [HotkeyAction: HotkeySpec] {
        var m: [HotkeyAction: HotkeySpec] = [:]
        for a in HotkeyAction.allCases { m[a] = hotkey(a) }
        return m
    }
}

// MARK: - 存储

final class Store: ObservableObject {
    static let shared = Store()

    @Published var skins: [Skin] = []
    @Published var masks: [MaskConfig] = []
    @Published var settings = GlobalSettings()
    @Published var activeMaskID: UUID? = nil

    private var loading = false
    private var needsSave = false

    private var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kagemaku", isDirectory: true)
    }
    private var skinsURL: URL { dir.appendingPathComponent("skins.json") }
    private var stateURL: URL { dir.appendingPathComponent("state.json") }

    private struct StateFile: Codable {
        var masks: [MaskConfig]
        var settings: GlobalSettings
        var version: Int? = nil
    }

    static let stateVersion = 2

    private init() {
        load()
    }

    func skin(_ id: UUID) -> Skin {
        skins.first(where: { $0.id == id }) ?? skins.first ?? SkinPresets.all[0]
    }

    func mask(_ id: UUID) -> MaskConfig? {
        masks.first(where: { $0.id == id })
    }

    func update(_ config: MaskConfig) {
        guard let i = masks.firstIndex(where: { $0.id == config.id }) else { return }
        if masks[i] != config {
            masks[i] = config
            save()
        }
    }

    func upsert(skin: Skin) {
        if let i = skins.firstIndex(where: { $0.id == skin.id }) {
            skins[i] = skin
        } else {
            skins.append(skin)
        }
        save()
    }

    func deleteSkin(_ id: UUID) {
        guard let s = skins.first(where: { $0.id == id }), !s.builtIn else { return }
        skins.removeAll { $0.id == id }
        let fallback = skins.first?.id ?? SkinPresets.all[0].id
        for i in masks.indices where masks[i].skinID == id {
            masks[i].skinID = fallback
        }
        save()
    }

    private func load() {
        loading = true
        defer { loading = false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var loaded = SkinPresets.all
        if let data = try? Data(contentsOf: skinsURL),
           let custom = try? JSONDecoder().decode([Skin].self, from: data) {
            loaded.append(contentsOf: custom.filter { !$0.builtIn })
        }
        skins = loaded

        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(StateFile.self, from: data) {
            settings = state.settings
            let stale = (state.version ?? 1) < Store.stateVersion
            masks = state.masks.map { m in
                var m = m
                if !skins.contains(where: { $0.id == m.skinID }) { m.skinID = skins[0].id }
                // 老存档里的部件是早期那套（只有一个时钟），换成现在的默认组合
                if stale && m.widgets.count <= 1 { m.widgets = MaskWidget.defaultSet }
                return m
            }
            needsSave = stale
        }
        if masks.isEmpty {
            masks = [defaultMask()]
        }
        activeMaskID = masks.first?.id
        if needsSave {
            needsSave = false
            loading = false
            save()
        }
    }

    func defaultMask() -> MaskConfig {
        var m = MaskConfig()
        m.skinID = skins.first?.id ?? SkinPresets.all[0].id
        if let screen = NSScreen.main {
            let f = screen.frame
            let w = min(1000, f.width * 0.62)
            let h: CGFloat = 104
            m.frame = CGRect(x: f.midX - w / 2, y: f.minY + f.height * 0.11, width: w, height: h)
        }
        return m
    }

    func save() {
        guard !loading else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(skins.filter { !$0.builtIn }) {
            try? d.write(to: skinsURL, options: .atomic)
        }
        if let d = try? enc.encode(StateFile(masks: masks, settings: settings, version: Store.stateVersion)) {
            try? d.write(to: stateURL, options: .atomic)
        }
    }
}

// MARK: - 宽容解码

// 存档缺字段时用默认值补齐，避免以后加了设置项就把旧存档整份读废。

extension KeyedDecodingContainer {
    func val<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return fallback
    }
}

extension Skin {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Skin()
        self.init()
        id = c.val(.id, d.id)
        name = c.val(.name, d.name)
        builtIn = c.val(.builtIn, d.builtIn)
        blur = c.val(.blur, d.blur)
        material = c.val(.material, d.material)
        appearance = c.val(.appearance, d.appearance)
        blurSaturation = c.val(.blurSaturation, d.blurSaturation)
        tintTop = c.val(.tintTop, d.tintTop)
        tintBottom = c.val(.tintBottom, d.tintBottom)
        gradientAngle = c.val(.gradientAngle, d.gradientAngle)
        cornerRadius = c.val(.cornerRadius, d.cornerRadius)
        borderWidth = c.val(.borderWidth, d.borderWidth)
        borderTop = c.val(.borderTop, d.borderTop)
        borderBottom = c.val(.borderBottom, d.borderBottom)
        glowRadius = c.val(.glowRadius, d.glowRadius)
        glowColor = c.val(.glowColor, d.glowColor)
        effect = c.val(.effect, d.effect)
        effectColor = c.val(.effectColor, d.effectColor)
        effectIntensity = c.val(.effectIntensity, d.effectIntensity)
        effectSpeed = c.val(.effectSpeed, d.effectSpeed)
        innerHighlight = c.val(.innerHighlight, d.innerHighlight)
    }
}

extension MaskConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MaskConfig()
        self.init()
        id = c.val(.id, d.id)
        label = c.val(.label, d.label)
        frame = c.val(.frame, d.frame)
        skinID = c.val(.skinID, d.skinID)
        opacity = c.val(.opacity, d.opacity)
        locked = c.val(.locked, d.locked)
        hidden = c.val(.hidden, d.hidden)
        trackMode = c.val(.trackMode, d.trackMode)
        trackWindowID = try? c.decodeIfPresent(UInt32.self, forKey: .trackWindowID)
        trackWindowOwner = try? c.decodeIfPresent(String.self, forKey: .trackWindowOwner)
        anchorX = c.val(.anchorX, d.anchorX)
        anchorY = c.val(.anchorY, d.anchorY)
        anchorW = c.val(.anchorW, d.anchorW)
        anchorH = c.val(.anchorH, d.anchorH)
        widgets = c.val(.widgets, d.widgets)
    }
}

extension GlobalSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlobalSettings()
        self.init()
        peekOpacity = c.val(.peekOpacity, d.peekOpacity)
        peekHold = c.val(.peekHold, d.peekHold)
        detectSensitivity = c.val(.detectSensitivity, d.detectSensitivity)
        detectBand = c.val(.detectBand, d.detectBand)
        detectRateHz = c.val(.detectRateHz, d.detectRateHz)
        detectPadding = c.val(.detectPadding, d.detectPadding)
        reduceMotion = c.val(.reduceMotion, d.reduceMotion)
        hotkeysEnabled = c.val(.hotkeysEnabled, d.hotkeysEnabled)
        snapEdges = c.val(.snapEdges, d.snapEdges)
        aboveFullscreen = c.val(.aboveFullscreen, d.aboveFullscreen)
        hotkeys = c.val(.hotkeys, d.hotkeys)
    }
}
