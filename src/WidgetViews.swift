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
    private var pitch: CGFloat { max(1.8, size * 0.108) }

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
            content.fixedSize().offset(x: x)
        }
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.045),
                .init(color: .black, location: 0.955),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
    }
}

// MARK: - 单个部件
//
// 每个部件都是同一个结构：注记行 + 数值行。
// 注记行高度固定，所以整条上所有数值压在同一条基线轴上。

struct WidgetView: View {
    let widget: MaskWidget
    let parts: WidgetParts
    let r: ResolvedWidget
    /// 全条统一的数值行高度，保证不同装置的读数落在同一条轴上
    let rowHeight: CGFloat
    /// 跑马灯跑道宽度，由外面按量出来的左右簇宽度算好
    let marqueeWidth: CGFloat

    private var gap: CGFloat { r.captionSize * 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: r.captionSize * 0.24) {
            captionRow
            valueRow.frame(height: rowHeight, alignment: .center)
        }
    }

    private var captionRow: some View {
        Text(parts.caption)
            .font(.system(size: r.captionSize, weight: .semibold, design: .rounded))
            .tracking(r.captionSize * 0.09)
            .textCase(.uppercase)
            .foregroundStyle(r.dim)
            .lineLimit(1)
            .fixedSize()
            .frame(height: r.captionSize * 1.25, alignment: .leading)
            .opacity(parts.caption.isEmpty ? 0 : 1)
    }

    private var valueRow: some View {
        HStack(alignment: .center, spacing: gap) {
            if widget.marquee {
                MarqueeBox(containerWidth: max(120, marqueeWidth),
                           contentWidth: WidgetView.deviceWidth(r, parts.value),
                           speed: 46) {
                    device(parts.value)
                }
            } else {
                device(parts.value)
            }
            if !parts.suffix.isEmpty { suffixText }
            if !parts.delta.isEmpty { deltaText }
        }
    }

    private var suffixText: some View {
        Text(parts.suffix)
            .font(.system(size: r.captionSize * 1.2, weight: .medium, design: .rounded))
            .foregroundStyle(r.dim)
            .lineLimit(1)
            .fixedSize()
    }

    private var deltaText: some View {
        Text(parts.delta)
            .font(.system(size: r.captionSize * 1.18, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(parts.deltaUp ? r.up : r.down)
            .lineLimit(1)
            .fixedSize()
    }

    private func device(_ text: String) -> some View {
        deviceBody(text).lineLimit(1).fixedSize()
    }

    @ViewBuilder
    private func deviceBody(_ text: String) -> some View {
        // 七段管画不出千分位逗号，挤在一起反而看不清
        let t = r.style == .seg7 ? text.replacingOccurrences(of: ",", with: "") : text
        switch r.style {
        case .nixie: NixieView(text: t, size: r.size, color: r.ink)
        case .splitflap: SplitFlapView(text: t, size: r.size, color: r.ink)
        case .dotmatrix: DotMatrixView(text: t, size: r.size, color: r.ink)
        case .seg7: Seg7View(text: t, size: r.size, color: r.ink)
        case .neon: NeonTextView(text: t, size: r.size, color: r.ink)
        case .plain: PlainTextView(text: t, size: r.size, color: r.ink)
        }
    }

    /// 装置本体的宽度，用来算跑马灯跑道和分配空间
    static func deviceWidth(_ r: ResolvedWidget, _ text: String) -> CGFloat {
        let t = r.style == .seg7 ? text.replacingOccurrences(of: ",", with: "") : text
        let n = CGFloat(t.count)
        switch r.style {
        case .nixie: return n * (r.size * 0.80 + r.size * 0.07)
        case .splitflap: return n * (r.size * 0.80 + r.size * 0.09)
        case .seg7: return n * (r.size * 0.66 + r.size * 0.19)
        case .dotmatrix:
            let f = NSFont.monospacedSystemFont(ofSize: r.size, weight: .bold)
            return (t as NSString).size(withAttributes: [.font: f]).width + r.size * 0.52
        default:
            let f = NSFont.monospacedSystemFont(ofSize: r.size, weight: .medium)
            return (t as NSString).size(withAttributes: [.font: f]).width + r.size * 0.3
        }
    }

    /// 装置本体占的高度，用来算全条统一的数值行高
    static func deviceHeight(_ style: WidgetStyle, _ size: CGFloat) -> CGFloat {
        switch style {
        case .nixie: return size * 1.52
        case .splitflap: return size * 1.44
        case .seg7: return size * 1.22
        case .dotmatrix: return size * 1.40
        case .neon, .plain: return size * 1.30
        }
    }

    static func totalWidth(_ r: ResolvedWidget, _ p: WidgetParts) -> CGFloat {
        var w = deviceWidth(r, p.value)
        let cap = NSFont.systemFont(ofSize: r.captionSize * 1.2, weight: .medium)
        if !p.suffix.isEmpty {
            w += (p.suffix as NSString).size(withAttributes: [.font: cap]).width + r.captionSize * 0.5
        }
        if !p.delta.isEmpty {
            w += (p.delta as NSString).size(withAttributes: [.font: cap]).width + r.captionSize * 0.5
        }
        return w
    }
}

// MARK: - 部件层

struct WidgetLayer: View {
    let widgets: [MaskWidget]
    let themeID: String
    let opacity: Double
    @ObservedObject private var hub = DataHub.shared

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { ctx in
            GeometryReader { geo in
                content(geo.size, ctx.date)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func content(_ size: CGSize, _ now: Date) -> some View {
        let theme = DeviceTheme.by(themeID)
        let h = size.height
        var resolved: [UUID: (WidgetParts, ResolvedWidget)] = [:]
        for w in widgets where w.enabled {
            resolved[w.id] = (WidgetText.parts(w, now: now, hub: hub),
                              WidgetResolver.resolve(w, theme: theme, contentHeight: h))
        }
        let unit = WidgetRole.caption.size(in: h, scale: 1)
        let rowH = resolved.values
            .map { WidgetView.deviceHeight($0.1.style, $0.1.size) }
            .max() ?? unit * 2

        let gap = unit * 2
        let leftW = zoneWidth(0, resolved, unit)
        let rightW = zoneWidth(2, resolved, unit)
        let centerW = max(120, size.width - leftW - rightW - gap * 4)

        return HStack(spacing: gap) {
            zone(0, .leading, resolved, unit, rowH, centerW).frame(width: leftW, alignment: .leading)
            zone(1, .center, resolved, unit, rowH, centerW).frame(width: centerW, alignment: .center)
            zone(2, .trailing, resolved, unit, rowH, centerW).frame(width: rightW, alignment: .trailing)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// 一簇里非跑马灯部件量出来的总宽
    private func zoneWidth(_ align: Int,
                           _ resolved: [UUID: (WidgetParts, ResolvedWidget)],
                           _ unit: CGFloat) -> CGFloat {
        let list = widgets.filter { $0.enabled && $0.align == align && !$0.marquee }
        guard !list.isEmpty else { return 0 }
        var w: CGFloat = 0
        for item in list {
            guard let (p, r) = resolved[item.id] else { continue }
            w += WidgetView.totalWidth(r, p)
        }
        return w + unit * 1.6 * CGFloat(list.count - 1)
    }

    private func zone(_ align: Int, _ alignment: Alignment,
                      _ resolved: [UUID: (WidgetParts, ResolvedWidget)],
                      _ unit: CGFloat, _ rowH: CGFloat, _ centerW: CGFloat) -> some View {
        let list = widgets.filter { $0.enabled && $0.align == align }
        return HStack(alignment: .top, spacing: unit * 1.6) {
            ForEach(list) { w in
                if let (p, r) = resolved[w.id] {
                    WidgetView(widget: w, parts: p, r: r, rowHeight: rowH,
                               marqueeWidth: centerW)
                }
            }
        }
        .frame(alignment: alignment)
    }
}
