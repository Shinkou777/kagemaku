import AppKit
import SwiftUI

// MARK: - 工具条几何（AppKit 命中判定与 SwiftUI 绘制共用）

enum ToolItem: Int, CaseIterable {
    case lock, learn, track, skin, settings, hide

    /// 学外语时玻璃是固定的透明款，不给换皮肤
    static func items(for mode: MaskMode) -> [ToolItem] {
        mode == .learn ? [.lock, .learn, .track, .settings, .hide] : allCases
    }

    func symbol(locked: Bool) -> String {
        switch self {
        case .lock: return locked ? "lock.fill" : "lock.open"
        case .learn: return "character.book.closed"
        case .track: return "scope"
        case .skin: return "paintpalette"
        case .settings: return "slider.horizontal.3"
        case .hide: return "eye.slash"
        }
    }

    func tip(mode: MaskMode, locked: Bool) -> String {
        switch self {
        case .lock: return locked ? "解锁" : "锁定，鼠标点得到底下的播放器"
        case .learn: return mode == .learn ? "学外语：只盖中文（再点回到听力）" : "学外语：只盖中文"
        case .track: return "怎么跟住字幕"
        case .skin: return "换皮肤"
        case .settings: return "设置"
        case .hide: return "先藏起来，⌥⌘M 放回"
        }
    }
}

enum ToolbarLayout {
    static let size: CGFloat = 26
    static let gap: CGFloat = 5
    static let inset: CGFloat = 9
    static let edgeHot: CGFloat = 7

    static func width(_ n: Int) -> CGFloat {
        CGFloat(n) * size + CGFloat(max(0, n - 1)) * gap
    }

    /// 按钮行的上沿：条高够就贴顶，矮条就竖直居中
    static func top(in s: CGSize) -> CGFloat {
        max(2, min(inset, (s.height - size) / 2))
    }

    /// 条太窄放不下时，从追踪、皮肤开始往下撤
    static func fitting(_ items: [ToolItem], in s: CGSize) -> [ToolItem] {
        var list = items
        for drop in [ToolItem.skin, .track, .learn, .settings] {
            if width(list.count) + inset * 2 <= s.width { break }
            list.removeAll { $0 == drop }
        }
        return list
    }

    /// 顶部右侧一排（坐标系：左上为原点）
    static func rects(in s: CGSize, items: [ToolItem]) -> [(ToolItem, CGRect)] {
        let list = fitting(items, in: s)
        let x0 = max(inset, s.width - inset - width(list.count))
        let y0 = top(in: s)
        return list.enumerated().map { i, item in
            (item, CGRect(x: x0 + CGFloat(i) * (size + gap), y: y0, width: size, height: size))
        }
    }

    static func hit(_ p: CGPoint, in s: CGSize, items: [ToolItem]) -> ToolItem? {
        for (item, r) in rects(in: s, items: items) where r.insetBy(dx: -2, dy: -2).contains(p) { return item }
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
            // 极光的椭圆、流光的光带都比条身大，不钉住尺寸的话会把整层撑大：
            // 着色往条身外面多画一截，极光按撑大的框裁成一块硬边矩形（2026-10-30 曉光皮肤）
            ZStack {
                base(s)
                EffectLayer(skin: skin, size: s, reduceMotion: reduceMotion)
                    .frame(width: s.width, height: s.height)
                    .clipShape(shape(s))
                stroke(s)
            }
            .frame(width: s.width, height: s.height)
            .compositingGroup()
            .opacity(opacity)
            // 真机上的外发光由 GlowLayer 画在条身外面；设置页的小预览直接挂阴影
            .shadow(color: preview ? skin.glowColor.color : .clear,
                    radius: preview ? min(skin.glowRadius, Skin.maxGlow) * 0.6 : 0,
                    x: 0, y: preview ? min(skin.glowRadius, Skin.maxGlow) * 0.1 : 0)
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
