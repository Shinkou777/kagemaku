import AppKit
import SwiftUI

// MARK: - 毛玻璃桥接

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var appearance: NSAppearance?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        v.appearance = appearance
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.appearance = appearance
        v.state = .active
    }
}

// MARK: - 工具条几何（AppKit 命中判定与 SwiftUI 绘制共用）

enum ToolItem: Int, CaseIterable {
    case lock, track, skin, settings, close

    var symbol: String {
        switch self {
        case .lock: return "lock.open"
        case .track: return "scope"
        case .skin: return "paintpalette"
        case .settings: return "slider.horizontal.3"
        case .close: return "xmark"
        }
    }

    var tip: String {
        switch self {
        case .lock: return "锁定（鼠标穿透）"
        case .track: return "追踪模式"
        case .skin: return "切换皮肤"
        case .settings: return "设置"
        case .close: return "移除这条"
        }
    }
}

enum ToolbarLayout {
    static let size: CGFloat = 26
    static let gap: CGFloat = 5
    static let inset: CGFloat = 9
    static let edgeHot: CGFloat = 7

    static var width: CGFloat {
        CGFloat(ToolItem.allCases.count) * size + CGFloat(ToolItem.allCases.count - 1) * gap
    }

    /// 顶部右侧一排（坐标系：左上为原点）
    static func rects(in s: CGSize) -> [(ToolItem, CGRect)] {
        let items = ToolItem.allCases
        let total = width
        let x0 = max(inset, s.width - inset - total)
        let y0 = max(4, min(inset, (s.height - size) / 2))
        return items.enumerated().map { i, item in
            (item, CGRect(x: x0 + CGFloat(i) * (size + gap), y: y0, width: size, height: size))
        }
    }

    static func hit(_ p: CGPoint, in s: CGSize) -> ToolItem? {
        for (item, r) in rects(in: s) where r.insetBy(dx: -2, dy: -2).contains(p) { return item }
        return nil
    }
}

// MARK: - 噪点纹理

enum NoiseTexture {
    static let image: Image = {
        let n = 128
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let v = UInt8(truncatingIfNeeded: seed >> 24)
            bytes[i * 4 + 0] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
            bytes[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: n * 4, space: cs,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)!
        return Image(decorative: cg, scale: 1)
    }()
}

// MARK: - 角度换算

func gradientPoints(_ deg: Double) -> (UnitPoint, UnitPoint) {
    let r = deg * .pi / 180
    let dx = cos(r) / 2
    let dy = sin(r) / 2
    return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
}

// MARK: - 效果层

struct EffectLayer: View {
    let skin: Skin
    let size: CGSize
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch skin.effect {
            case .none:
                Color.clear
            case .shimmer:
                shimmer
            case .scanline:
                scanline
            case .aurora:
                aurora
            case .pulse:
                Color.clear
            case .grain:
                grain
            case .frost:
                frost
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private var frozen: Bool { reduceMotion || !skin.effect.animated }

    private func phase(_ ctx: TimelineViewDefaultContext, cycle: Double) -> Double {
        let t = ctx.date.timeIntervalSinceReferenceDate * max(0.05, skin.effectSpeed)
        return (t.truncatingRemainder(dividingBy: cycle)) / cycle
    }

    // 流光
    private var shimmer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: frozen)) { ctx in
            let raw = frozen ? 0.35 : phase(ctx, cycle: 7.0)
            // 前 40% 扫过去，后面歇着，免得一直在闪
            let p = min(1.0, raw / 0.4)
            let bandW = min(max(70, size.width * 0.13), 200)
            let travel = size.width + bandW * 2
            LinearGradient(colors: [.clear,
                                    skin.effectColor.color.opacity(skin.effectIntensity * 0.35),
                                    skin.effectColor.color.opacity(skin.effectIntensity * 1.3),
                                    skin.effectColor.color.opacity(skin.effectIntensity * 0.35),
                                    .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: bandW, height: hypot(size.width, size.height) * 1.25)
                .rotationEffect(.degrees(16))
                .offset(x: -size.width / 2 - bandW + p * travel)
        }
    }

    // CRT 扫描线
    private var scanline: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: frozen)) { ctx in
            let p = frozen ? 0 : phase(ctx, cycle: 2.4)
            Canvas { gc, sz in
                let step: CGFloat = 3
                let color = skin.effectColor.color.opacity(skin.effectIntensity * 0.55)
                var y = -step + CGFloat(p) * step
                while y < sz.height {
                    gc.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 1)), with: .color(color))
                    y += step
                }
                let sweepY = CGFloat(p) * (sz.height + 40) - 20
                gc.fill(Path(CGRect(x: 0, y: sweepY, width: sz.width, height: 10)),
                        with: .linearGradient(
                            Gradient(colors: [.clear, skin.effectColor.color.opacity(skin.effectIntensity * 0.5), .clear]),
                            startPoint: CGPoint(x: 0, y: sweepY),
                            endPoint: CGPoint(x: 0, y: sweepY + 10)))
            }
        }
    }

    // 极光
    private var aurora: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: frozen)) { ctx in
            let t = frozen ? 0.0 : ctx.date.timeIntervalSinceReferenceDate * max(0.05, skin.effectSpeed) * 0.35
            ZStack {
                blob(hue: skin.effectColor.color, dx: sin(t) * 0.34, dy: cos(t * 0.8) * 0.22, scale: 0.9)
                blob(hue: Color(red: 0.72, green: 0.45, blue: 1.0), dx: sin(t * 0.7 + 2.1) * 0.4, dy: sin(t * 1.1) * 0.26, scale: 1.1)
                blob(hue: Color(red: 1.0, green: 0.55, blue: 0.82), dx: cos(t * 0.55 + 4.0) * 0.36, dy: cos(t * 0.9 + 1.0) * 0.2, scale: 0.75)
            }
        }
    }

    private func blob(hue: Color, dx: Double, dy: Double, scale: Double) -> some View {
        Ellipse()
            .fill(hue.opacity(skin.effectIntensity * 0.7))
            .frame(width: size.width * 0.55 * scale, height: size.height * 1.5 * scale)
            .blur(radius: max(14, size.height * 0.35))
            .offset(x: size.width * dx, y: size.height * dy)
    }

    // 颗粒
    private var grain: some View {
        NoiseTexture.image
            .resizable(resizingMode: .tile)
            .opacity(skin.effectIntensity * 0.28)
    }

    // 霜面
    private var frost: some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(skin.effectIntensity * 0.18), .clear],
                           center: .top, startRadius: 0, endRadius: max(size.width, 1) * 0.7)
            NoiseTexture.image
                .resizable(resizingMode: .tile)
                .opacity(skin.effectIntensity * 0.10)
        }
    }
}

// MARK: - 皮肤主体

struct SkinLayer: View {
    let skin: Skin
    let opacity: Double
    let reduceMotion: Bool
    /// true 时用 SwiftUI Material 模拟玻璃（设置页预览）；
    /// false 时玻璃由 AppKit 的 NSVisualEffectView 画在底下，这里只画着色层
    var preview: Bool = false

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                base(s)
                EffectLayer(skin: skin, size: s, reduceMotion: reduceMotion)
                    .clipShape(shape(s))
                stroke(s)
            }
            .compositingGroup()
            .opacity(opacity)
            .shadow(color: skin.glowColor.color, radius: skin.glowRadius, x: 0, y: skin.glowRadius * 0.18)
        }
    }

    /// 玻璃层用 NSBezierPath 画圆角（正圆弧），这里必须同一种曲线，
    /// 否则四个角上玻璃和描边错开，边缘看着发怪
    private func shape(_ s: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Skin.clampRadius(skin.cornerRadius, s), style: .circular)
    }

    private func base(_ sz: CGSize) -> some View {
        let pts = gradientPoints(skin.gradientAngle)
        return ZStack {
            if preview && skin.blur {
                skin.material.previewMaterial
                    .saturation(skin.blurSaturation)
                    .environment(\.colorScheme, skin.appearance == .light ? .light : .dark)
            }
            LinearGradient(colors: [skin.tintTop.color, skin.tintBottom.color],
                           startPoint: pts.0, endPoint: pts.1)
            VStack(spacing: 0) {
                LinearGradient(colors: [.white.opacity(skin.innerHighlight * 0.5), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .clipShape(shape(sz))
    }

    private func stroke(_ sz: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0,
                                paused: reduceMotion || skin.effect != .pulse)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate * max(0.05, skin.effectSpeed)
            let breathe = skin.effect == .pulse && !reduceMotion
                ? 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 1.6))
                : 1.0
            shape(sz)
                .strokeBorder(LinearGradient(colors: [skin.borderTop.color, skin.borderBottom.color],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: skin.borderWidth)
                .opacity(breathe)
        }
    }
}
