import Foundation

enum SkinPresets {

    private static func uid(_ s: String) -> UUID {
        UUID(uuidString: s) ?? UUID()
    }

    static let all: [Skin] = [frosted, neonNoir, aurora, sumi, scanline, milk, mosaic]

    // 1. 霧硝子 — 默认。纯毛玻璃，细白边，极淡流光
    static var frosted: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000001")
        s.name = "霧硝子 Frosted"
        s.builtIn = true
        s.blur = true
        s.material = .hud
        s.appearance = .dark
        s.blurSaturation = 1.05
        s.tintTop = RGBA(hex: "#EAF2FF", alpha: 0.10)
        s.tintBottom = RGBA(hex: "#7C8CA8", alpha: 0.04)
        s.gradientAngle = 100
        s.cornerRadius = 18
        s.borderWidth = 1
        s.borderTop = RGBA(hex: "#FFFFFF", alpha: 0.38)
        s.borderBottom = RGBA(hex: "#FFFFFF", alpha: 0.06)
        s.glowRadius = 24
        s.glowColor = RGBA(hex: "#000000", alpha: 0.5)
        s.effect = .shimmer
        s.effectColor = RGBA(hex: "#FFFFFF", alpha: 0.45)
        s.effectIntensity = 0.28
        s.effectSpeed = 0.55
        s.innerHighlight = 0.42
        return s
    }

    // 2. 深夜霓虹
    static var neonNoir: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000002")
        s.name = "深夜霓虹 Neon Noir"
        s.builtIn = true
        s.blur = true
        s.material = .underWindow
        s.appearance = .dark
        s.blurSaturation = 0.8
        s.tintTop = RGBA(hex: "#1A0033", alpha: 0.62)
        s.tintBottom = RGBA(hex: "#00141F", alpha: 0.72)
        s.gradientAngle = 115
        s.cornerRadius = 14
        s.borderWidth = 1.6
        s.borderTop = RGBA(hex: "#FF2D95", alpha: 0.95)
        s.borderBottom = RGBA(hex: "#00E5FF", alpha: 0.9)
        s.glowRadius = 30
        s.glowColor = RGBA(hex: "#FF2D95", alpha: 0.5)
        s.effect = .pulse
        s.effectColor = RGBA(hex: "#00E5FF", alpha: 0.85)
        s.effectIntensity = 0.5
        s.effectSpeed = 0.8
        s.innerHighlight = 0.2
        return s
    }

    // 3. 曉光 — 极光流动
    static var aurora: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000003")
        s.name = "曉光 Aurora"
        s.builtIn = true
        s.blur = true
        s.material = .hud
        s.appearance = .dark
        s.blurSaturation = 1.2
        s.tintTop = RGBA(hex: "#0B1026", alpha: 0.5)
        s.tintBottom = RGBA(hex: "#160A2B", alpha: 0.58)
        s.gradientAngle = 90
        s.cornerRadius = 22
        s.borderWidth = 1
        s.borderTop = RGBA(hex: "#9DF7FF", alpha: 0.55)
        s.borderBottom = RGBA(hex: "#C79BFF", alpha: 0.35)
        s.glowRadius = 34
        s.glowColor = RGBA(hex: "#6E5BFF", alpha: 0.45)
        s.effect = .aurora
        s.effectColor = RGBA(hex: "#7AF5FF", alpha: 0.8)
        s.effectIntensity = 0.55
        s.effectSpeed = 0.5
        s.innerHighlight = 0.3
        return s
    }

    // 4. 墨 — 全不透明，彻底遮死
    static var sumi: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000004")
        s.name = "墨 Sumi"
        s.builtIn = true
        s.blur = false
        s.material = .underWindow
        s.appearance = .dark
        s.tintTop = RGBA(hex: "#0C0C10", alpha: 1)
        s.tintBottom = RGBA(hex: "#141419", alpha: 1)
        s.gradientAngle = 90
        s.cornerRadius = 6
        s.borderWidth = 0.8
        s.borderTop = RGBA(hex: "#C9A227", alpha: 0.75)
        s.borderBottom = RGBA(hex: "#7A5F14", alpha: 0.4)
        s.glowRadius = 12
        s.glowColor = RGBA(hex: "#000000", alpha: 0.6)
        s.effect = .grain
        s.effectColor = RGBA(hex: "#FFFFFF", alpha: 0.5)
        s.effectIntensity = 0.18
        s.effectSpeed = 0
        s.innerHighlight = 0.1
        return s
    }

    // 5. CRT 走査線
    static var scanline: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000005")
        s.name = "走査線 CRT"
        s.builtIn = true
        s.blur = true
        s.material = .menu
        s.appearance = .dark
        s.blurSaturation = 0.6
        s.tintTop = RGBA(hex: "#001A0E", alpha: 0.72)
        s.tintBottom = RGBA(hex: "#00120C", alpha: 0.8)
        s.gradientAngle = 90
        s.cornerRadius = 8
        s.borderWidth = 1.2
        s.borderTop = RGBA(hex: "#39FF14", alpha: 0.7)
        s.borderBottom = RGBA(hex: "#0B6B23", alpha: 0.5)
        s.glowRadius = 26
        s.glowColor = RGBA(hex: "#39FF14", alpha: 0.35)
        s.effect = .scanline
        s.effectColor = RGBA(hex: "#8CFFA8", alpha: 0.5)
        s.effectIntensity = 0.4
        s.effectSpeed = 0.7
        s.innerHighlight = 0.15
        return s
    }

    // 6. 曇りガラス — 亮场景用
    static var milk: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000006")
        s.name = "曇硝子 Milk"
        s.builtIn = true
        s.blur = true
        s.material = .popover
        s.appearance = .light
        s.blurSaturation = 1.1
        s.tintTop = RGBA(hex: "#FFFFFF", alpha: 0.42)
        s.tintBottom = RGBA(hex: "#E7ECF5", alpha: 0.3)
        s.gradientAngle = 90
        s.cornerRadius = 20
        s.borderWidth = 1
        s.borderTop = RGBA(hex: "#FFFFFF", alpha: 0.9)
        s.borderBottom = RGBA(hex: "#B9C3D6", alpha: 0.5)
        s.glowRadius = 20
        s.glowColor = RGBA(hex: "#2A3550", alpha: 0.28)
        s.effect = .none
        s.effectColor = RGBA(hex: "#FFFFFF", alpha: 0.5)
        s.effectIntensity = 0.2
        s.effectSpeed = 0.5
        s.innerHighlight = 0.5
        return s
    }

    // 7. モザイク — 强模糊 + 提色，看得见色块看不清字
    static var mosaic: Skin {
        var s = Skin()
        s.id = uid("11111111-0000-4000-A000-000000000007")
        s.name = "モザイク Mosaic"
        s.builtIn = true
        s.blur = true
        s.material = .fullScreenUI
        s.appearance = .system
        s.blurSaturation = 1.8
        s.tintTop = RGBA(hex: "#FFFFFF", alpha: 0.04)
        s.tintBottom = RGBA(hex: "#000000", alpha: 0.10)
        s.gradientAngle = 90
        s.cornerRadius = 12
        s.borderWidth = 1
        s.borderTop = RGBA(hex: "#FFFFFF", alpha: 0.24)
        s.borderBottom = RGBA(hex: "#000000", alpha: 0.2)
        s.glowRadius = 16
        s.glowColor = RGBA(hex: "#000000", alpha: 0.4)
        s.effect = .frost
        s.effectColor = RGBA(hex: "#FFFFFF", alpha: 0.5)
        s.effectIntensity = 0.5
        s.effectSpeed = 0
        s.innerHighlight = 0.25
        return s
    }
}
