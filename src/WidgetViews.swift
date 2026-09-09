import AppKit
import SwiftUI

// MARK: - 辉光管

struct NixieView: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: size * 0.11) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                tube(String(ch))
            }
        }
    }

    private func tube(_ ch: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.black.opacity(0.30)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.7)
            Text(ch)
                .font(.system(size: size, weight: .medium, design: .serif))
                .foregroundStyle(color.opacity(0.13))
            Text(ch)
                .font(.system(size: size, weight: .medium, design: .serif))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.95), radius: size * 0.16)
                .shadow(color: color.opacity(0.55), radius: size * 0.42)
        }
        .frame(width: size * 0.74, height: size * 1.32)
    }
}

// MARK: - 翻页牌

struct SplitFlapView: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                FlapCell(ch: String(ch), size: size, color: color)
            }
        }
    }
}

struct FlapCell: View {
    let ch: String
    let size: CGFloat
    let color: Color

    @State private var shown: String = " "
    @State private var folded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
            Text(shown)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .rotation3DEffect(.degrees(folded ? -88 : 0), axis: (x: 1, y: 0, z: 0),
                                  anchor: .center, perspective: 0.55)
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(height: 1)
        }
        .frame(width: size * 0.72, height: size * 1.28)
        .onAppear { shown = ch }
        .onChange(of: ch) { _, new in flip(to: new) }
    }

    private func flip(to new: String) {
        withAnimation(.easeIn(duration: 0.07)) { folded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            shown = new
            withAnimation(.easeOut(duration: 0.13)) { folded = false }
        }
    }
}

// MARK: - 点阵

struct DotMatrixView: View {
    let text: String
    let size: CGFloat
    let color: Color

    private var font: Font { .system(size: size, weight: .bold, design: .monospaced) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.clear)
            .padding(.horizontal, size * 0.18)
            .padding(.vertical, size * 0.16)
            .overlay { lit }
    }

    private var lit: some View {
        ZStack {
            dots(color.opacity(0.12))
            dots(color)
                .mask(Text(text).font(font))
                .shadow(color: color.opacity(0.6), radius: size * 0.2)
        }
    }

    private func dots(_ c: Color) -> some View {
        Canvas { gc, sz in
            let pitch = max(2.6, size * 0.165)
            let r = pitch * 0.36
            var y = pitch / 2
            while y < sz.height {
                var x = pitch / 2
                while x < sz.width {
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(c))
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
        "-": 0x40, "_": 0x08, " ": 0x00,
    ]

    var body: some View {
        HStack(spacing: size * 0.13) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                cell(ch)
            }
        }
    }

    @ViewBuilder
    private func cell(_ ch: Character) -> some View {
        if let mask = Seg7View.map[ch] {
            digit(mask)
        } else if ch == ":" || ch == "." || ch == "," {
            punct(ch)
        } else {
            Text(String(ch))
                .font(.system(size: size * 0.82, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: size * 0.18)
                .frame(height: size * 1.3)
        }
    }

    private func digit(_ mask: UInt8) -> some View {
        Canvas { gc, sz in
            let t = sz.height * 0.13
            let on = color
            let off = color.opacity(0.09)
            let segs = Seg7View.segments(sz, t)
            for (i, rect) in segs.enumerated() {
                let lit = (mask >> UInt8(i)) & 1 == 1
                gc.fill(Path(roundedRect: rect, cornerRadius: t * 0.42),
                        with: .color(lit ? on : off))
            }
        }
        .frame(width: size * 0.64, height: size * 1.3)
        .shadow(color: color.opacity(0.45), radius: size * 0.16)
    }

    private func punct(_ ch: Character) -> some View {
        Canvas { gc, sz in
            let d = sz.height * 0.12
            let x = sz.width / 2 - d / 2
            if ch == ":" {
                gc.fill(Path(ellipseIn: CGRect(x: x, y: sz.height * 0.30, width: d, height: d)), with: .color(color))
                gc.fill(Path(ellipseIn: CGRect(x: x, y: sz.height * 0.62, width: d, height: d)), with: .color(color))
            } else {
                gc.fill(Path(ellipseIn: CGRect(x: x, y: sz.height * 0.78, width: d, height: d)), with: .color(color))
            }
        }
        .frame(width: size * 0.26, height: size * 1.3)
        .shadow(color: color.opacity(0.45), radius: size * 0.14)
    }

    /// 顺序 a b c d e f g
    static func segments(_ s: CGSize, _ t: CGFloat) -> [CGRect] {
        let w = s.width, h = s.height
        let p = t * 0.85
        let midY = h / 2 - t / 2
        return [
            CGRect(x: p, y: 0, width: w - p * 2, height: t),                       // a 上
            CGRect(x: w - t, y: p, width: t, height: midY - p + t * 0.2),          // b 右上
            CGRect(x: w - t, y: midY + t * 0.8, width: t, height: h - midY - t * 1.6 - p * 0.2), // c 右下
            CGRect(x: p, y: h - t, width: w - p * 2, height: t),                   // d 下
            CGRect(x: 0, y: midY + t * 0.8, width: t, height: h - midY - t * 1.6 - p * 0.2),     // e 左下
            CGRect(x: 0, y: p, width: t, height: midY - p + t * 0.2),              // f 左上
            CGRect(x: p, y: midY, width: w - p * 2, height: t),                    // g 中
        ]
    }
}

// MARK: - 霓虹 / 简约

struct NeonTextView: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.96))
            .shadow(color: color, radius: size * 0.10)
            .shadow(color: color.opacity(0.85), radius: size * 0.32)
            .shadow(color: color.opacity(0.5), radius: size * 0.75)
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
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
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
            let span = contentWidth + containerWidth * 0.6
            let t = ctx.date.timeIntervalSinceReferenceDate * speed
            let x = containerWidth - CGFloat(t.truncatingRemainder(dividingBy: span))
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
            MarqueeBox(containerWidth: max(80, containerWidth),
                       contentWidth: WidgetView.width(widget, text),
                       speed: 42) {
                styled
            }
        } else {
            styled
        }
    }

    @ViewBuilder
    private var styled: some View {
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
        case .nixie: return n * (w.size * 0.74 + w.size * 0.11)
        case .splitflap: return n * (w.size * 0.72 + 2.5)
        case .seg7: return n * (w.size * 0.64 + w.size * 0.13)
        default:
            let f = NSFont.monospacedSystemFont(ofSize: w.size, weight: .bold)
            return (text as NSString).size(withAttributes: [.font: f]).width + w.size * 0.4
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
                ZStack {
                    group(0, .leading, geo.size, ctx.date)
                    group(1, .center, geo.size, ctx.date)
                    group(2, .trailing, geo.size, ctx.date)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func group(_ align: Int, _ alignment: Alignment, _ size: CGSize, _ now: Date) -> some View {
        let list = widgets.filter { $0.enabled && $0.align == align }
        return HStack(spacing: 14) {
            ForEach(list) { w in
                WidgetView(widget: w,
                           text: WidgetText.value(w, now: now, hub: hub),
                           containerWidth: containerWidth(w, size))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func containerWidth(_ w: MaskWidget, _ size: CGSize) -> CGFloat {
        let others = widgets.filter { $0.enabled && $0.align == w.align && $0.id != w.id }
        let reserved = CGFloat(others.count) * 140
        return max(120, size.width - 32 - reserved)
    }
}
