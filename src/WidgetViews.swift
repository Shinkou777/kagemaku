import AppKit
import SwiftUI

// MARK: - 辉光管

struct NixieView: View {
    let text: String
    let size: CGFloat
    let color: Color

    private var tubeW: CGFloat { size * 0.80 }
    private var tubeH: CGFloat { size * 1.52 }

    var body: some View {
        HStack(spacing: size * 0.07) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == " " {
                    Color.clear.frame(width: tubeW * 0.45, height: tubeH)
                } else {
                    tube(String(ch))
                }
            }
        }
    }

    private func tube(_ ch: String) -> some View {
        ZStack {
            glassBody
            glowPool
            glyph(ch).foregroundStyle(color.opacity(0.09))
            litGlyph(ch)
            mesh
            specular
            rim
        }
        .frame(width: tubeW, height: tubeH)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: tubeW * 0.42, style: .continuous)
    }

    private var glassBody: some View {
        shape.fill(
            LinearGradient(colors: [Color.black.opacity(0.30),
                                    Color.black.opacity(0.52),
                                    Color.black.opacity(0.40)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var glowPool: some View {
        Ellipse()
            .fill(RadialGradient(colors: [color.opacity(0.34), color.opacity(0.06), .clear],
                                 center: .center, startRadius: 0, endRadius: tubeW * 0.72))
            .frame(width: tubeW * 1.35, height: tubeH * 0.72)
            .blur(radius: size * 0.13)
    }

    private func glyph(_ ch: String) -> some View {
        Text(ch)
            .font(.system(size: size * 0.94, weight: .regular, design: .serif))
            .monospacedDigit()
    }

    private func litGlyph(_ ch: String) -> some View {
        glyph(ch)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.95), color, color.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom))
            .shadow(color: color.opacity(0.95), radius: size * 0.07)
            .shadow(color: color.opacity(0.70), radius: size * 0.20)
            .shadow(color: color.opacity(0.40), radius: size * 0.48)
    }

    /// 阴极网罩
    private var mesh: some View {
        Canvas { gc, sz in
            let step = max(1.6, size * 0.11)
            var x = step / 2
            while x < sz.width {
                gc.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: sz.height)),
                        with: .color(.white.opacity(0.038)))
                x += step
            }
        }
        .clipShape(shape)
    }

    /// 玻璃上的一道反光
    private var specular: some View {
        RoundedRectangle(cornerRadius: tubeW * 0.2, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.02), .clear],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: tubeW * 0.16, height: tubeH * 0.62)
            .offset(x: -tubeW * 0.24, y: -tubeH * 0.10)
            .blur(radius: 0.6)
    }

    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.04), .white.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 0.8)
    }
}

// MARK: - 翻页牌

struct SplitFlapView: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: size * 0.09) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == " " {
                    Color.clear.frame(width: size * 0.30, height: size * 1.44)
                } else {
                    FlapCell(ch: String(ch), size: size, color: color)
                }
            }
        }
    }
}

struct FlapCell: View {
    let ch: String
    let size: CGFloat
    let color: Color

    @State private var shown: String = " "
    @State private var fold: Double = 0     // 上半页往下折
    @State private var unfold: Double = 0   // 下半页往上抬

    private var w: CGFloat { size * 0.80 }
    private var h: CGFloat { size * 1.44 }
    private var seam: CGFloat { max(1, size * 0.055) }
    private var halfH: CGFloat { (h - seam) / 2 }

    var body: some View {
        ZStack {
            VStack(spacing: seam) {
                half(top: true)
                    .rotation3DEffect(.degrees(-92 * fold), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.5)
                half(top: false)
                    .rotation3DEffect(.degrees(92 * unfold), axis: (x: 1, y: 0, z: 0),
                                      anchor: .top, perspective: 0.5)
            }
            pivots
        }
        .frame(width: w, height: h)
        .onAppear { shown = ch }
        .onChange(of: ch) { _, new in flip(to: new) }
    }

    private func flip(to new: String) {
        withAnimation(.easeIn(duration: 0.08)) { fold = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.085) {
            shown = new
            fold = 0
            unfold = 1
            withAnimation(.easeOut(duration: 0.13)) { unfold = 0 }
        }
    }

    private func half(top: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .fill(LinearGradient(
                    colors: top ? [Color(white: 0.215), Color(white: 0.145)]
                                : [Color(white: 0.125), Color(white: 0.075)],
                    startPoint: .top, endPoint: .bottom))
            Text(shown)
                .font(.system(size: size * 0.96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
                .frame(width: w, height: h)
                .offset(y: top ? (halfH + seam) / 2 : -(halfH + seam) / 2)
        }
        .frame(width: w, height: halfH)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .strokeBorder(Color.white.opacity(top ? 0.10 : 0.05), lineWidth: 0.7)
        )
    }

    private var pivots: some View {
        HStack {
            Circle().fill(Color(white: 0.42))
            Spacer()
            Circle().fill(Color(white: 0.42))
        }
        .frame(width: w + size * 0.10, height: size * 0.10)
    }
}

// MARK: - 点阵

struct DotMatrixView: View {
    let text: String
    let size: CGFloat
    let color: Color

    private var font: Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
    private var pitch: CGFloat { max(2.0, size * 0.135) }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.clear)
            .padding(.horizontal, size * 0.26)
            .padding(.vertical, size * 0.20)
            .background(panel)
            .overlay { leds }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(Color.black.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.7))
    }

    private var leds: some View {
        ZStack {
            grid(color.opacity(0.085))
            grid(color)
                .mask(Text(text).font(font).lineLimit(1).fixedSize())
                .shadow(color: color.opacity(0.55), radius: size * 0.16)
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private func grid(_ c: Color) -> some View {
        Canvas { gc, sz in
            let d = pitch * 0.70
            let r = d * 0.34
            var y = pitch * 0.5
            while y < sz.height {
                var x = pitch * 0.5
                while x < sz.width {
                    let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                    gc.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(c))
                    x += pitch
                }
                y += pitch
            }
        }
    }
}

// MARK: - 七段数码管

struct Seg7View: View {
    let text: String
    let size: CGFloat
    let color: Color

    private static let map: [Character: UInt8] = [
        "0": 0x3F, "1": 0x06, "2": 0x5B, "3": 0x4F, "4": 0x66,
        "5": 0x6D, "6": 0x7D, "7": 0x07, "8": 0x7F, "9": 0x6F,
        "-": 0x40, "_": 0x08,
        "A": 0x77, "b": 0x7C, "C": 0x39, "d": 0x5E, "E": 0x79, "F": 0x71,
        "H": 0x76, "L": 0x38, "P": 0x73, "U": 0x3E, "n": 0x54, "o": 0x5C, "r": 0x50,
    ]

    private var cellW: CGFloat { size * 0.66 }
    private var cellH: CGFloat { size * 1.22 }

    var body: some View {
        HStack(spacing: size * 0.19) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                cell(ch)
            }
        }
    }

    @ViewBuilder
    private func cell(_ ch: Character) -> some View {
        if ch == " " {
            Color.clear.frame(width: cellW * 0.42, height: cellH)
        } else if let mask = Seg7View.map[ch] {
            digit(mask)
        } else if ch == ":" || ch == "." || ch == "," || ch == "%" || ch == "+" {
            punct(ch)
        } else {
            Text(String(ch))
                .font(.system(size: size * 0.74, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
                .shadow(color: color.opacity(0.5), radius: size * 0.14)
                .frame(height: cellH)
        }
    }

    private func digit(_ mask: UInt8) -> some View {
        Canvas { gc, sz in
            let segs = Seg7View.segments(sz)
            for (i, seg) in segs.enumerated() {
                let lit = (mask >> UInt8(i)) & 1 == 1
                gc.fill(seg, with: .color(lit ? color : color.opacity(0.045)))
            }
        }
        .frame(width: cellW, height: cellH)
        .shadow(color: color.opacity(0.45), radius: size * 0.10)
    }

    private func punct(_ ch: Character) -> some View {
        Group {
            if ch == ":" {
                VStack(spacing: cellH * 0.22) {
                    dot; dot
                }
            } else if ch == "." || ch == "," {
                VStack { Spacer(); dot }
            } else {
                Text(String(ch))
                    .font(.system(size: size * 0.6, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size * 0.26, height: cellH)
        .shadow(color: color.opacity(0.5), radius: size * 0.12)
    }

    private var dot: some View {
        Circle().fill(color).frame(width: size * 0.13, height: size * 0.13)
    }

    /// 顺序 a b c d e f g，六边形段带斜切端头
    static func segments(_ s: CGSize) -> [Path] {
        let w = s.width, h = s.height
        let t = h * 0.125
        let g = t * 0.85
        let vH = (h - t) / 2 - 2 * g
        let hRect = { (y: CGFloat) in CGRect(x: g, y: y, width: w - 2 * g, height: t) }
        let vRect = { (x: CGFloat, y: CGFloat) in CGRect(x: x, y: y, width: t, height: vH) }
        return [
            hPath(hRect(0)),
            vPath(vRect(w - t, g)),
            vPath(vRect(w - t, (h + t) / 2 + g)),
            hPath(hRect(h - t)),
            vPath(vRect(0, (h + t) / 2 + g)),
            vPath(vRect(0, g)),
            hPath(hRect((h - t) / 2)),
        ]
    }

    static func hPath(_ r: CGRect) -> Path {
        let t = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX + t / 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t / 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - t / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + t / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }

    static func vPath(_ r: CGRect) -> Path {
        let t = r.width
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + t / 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + t / 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - t / 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - t / 2))
        p.closeSubpath()
        return p
    }
}

// MARK: - 霓虹 / 简约

struct NeonTextView: View {
    let text: String
    let size: CGFloat
    let color: Color

    private var font: Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    var body: some View {
        ZStack {
            Text(text).font(font).foregroundStyle(color)
                .blur(radius: size * 0.28)
                .opacity(0.9)
            Text(text).font(font).foregroundStyle(color)
                .blur(radius: size * 0.09)
            Text(text).font(font)
                .foregroundStyle(Color.white.opacity(0.97))
                .shadow(color: color, radius: size * 0.08)
        }
    }
}

struct PlainTextView: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
    }
}

// MARK: - 跑马灯

struct MarqueeBox<Content: View>: View {
    let containerWidth: CGFloat
    let contentWidth: CGFloat
    let speed: Double
    @ViewBuilder var content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let span = contentWidth + containerWidth * 0.5
            let t = ctx.date.timeIntervalSinceReferenceDate * speed
            let x = containerWidth - CGFloat(t.truncatingRemainder(dividingBy: max(1, span)))
            content.offset(x: x)
        }
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
    }
}

// MARK: - 单个部件

struct WidgetView: View {
    let widget: MaskWidget
    let text: String
    let containerWidth: CGFloat

    var body: some View {
        if widget.marquee {
            MarqueeBox(containerWidth: max(90, containerWidth),
                       contentWidth: WidgetView.width(widget, text),
                       speed: 46) {
                styled
            }
        } else {
            styled
        }
    }

    @ViewBuilder
    private var styled: some View {
        rendered.lineLimit(1).fixedSize()
    }

    @ViewBuilder
    private var rendered: some View {
        let c = widget.color.color
        switch widget.style {
        case .nixie: NixieView(text: text, size: widget.size, color: c)
        case .splitflap: SplitFlapView(text: text, size: widget.size, color: c)
        case .dotmatrix: DotMatrixView(text: text, size: widget.size, color: c)
        case .seg7: Seg7View(text: text, size: widget.size, color: c)
        case .neon: NeonTextView(text: text, size: widget.size, color: c)
        case .plain: PlainTextView(text: text, size: widget.size, color: c)
        }
    }

    static func width(_ w: MaskWidget, _ text: String) -> CGFloat {
        let n = CGFloat(text.count)
        switch w.style {
        case .nixie: return n * (w.size * 0.80 + w.size * 0.07)
        case .splitflap: return n * (w.size * 0.80 + w.size * 0.09)
        case .seg7: return n * (w.size * 0.66 + w.size * 0.19)
        case .dotmatrix:
            let f = NSFont.monospacedSystemFont(ofSize: w.size, weight: .bold)
            return (text as NSString).size(withAttributes: [.font: f]).width + w.size * 0.52
        default:
            let f = NSFont.monospacedSystemFont(ofSize: w.size, weight: .medium)
            return (text as NSString).size(withAttributes: [.font: f]).width + w.size * 0.3
        }
    }
}

// MARK: - 部件层

struct WidgetLayer: View {
    let widgets: [MaskWidget]
    let opacity: Double
    @ObservedObject private var hub = DataHub.shared

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { ctx in
            GeometryReader { geo in
                content(geo.size, ctx.date)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func content(_ size: CGSize, _ now: Date) -> some View {
        let texts = resolved(now)
        return ZStack {
            group(0, .leading, size, texts)
            group(1, .center, size, texts)
            group(2, .trailing, size, texts)
        }
    }

    private func resolved(_ now: Date) -> [UUID: String] {
        var m: [UUID: String] = [:]
        for w in widgets where w.enabled {
            m[w.id] = WidgetText.value(w, now: now, hub: hub)
        }
        return m
    }

    private func group(_ align: Int, _ alignment: Alignment, _ size: CGSize,
                       _ texts: [UUID: String]) -> some View {
        let list = widgets.filter { $0.enabled && $0.align == align }
        return HStack(spacing: 12) {
            ForEach(list) { w in
                WidgetView(widget: w,
                           text: texts[w.id] ?? "",
                           containerWidth: room(w, size, texts))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// 跑马灯能占多宽：整条减掉别的部件实际量出来的宽度
    private func room(_ w: MaskWidget, _ size: CGSize, _ texts: [UUID: String]) -> CGFloat {
        var used: CGFloat = 0
        for other in widgets where other.enabled && other.id != w.id {
            if other.marquee { continue }
            used += WidgetView.width(other, texts[other.id] ?? "") + 12
        }
        return max(120, size.width - 28 - used)
    }
}
