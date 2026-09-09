import AppKit

// 生成 /tmp/Kagemaku.iconset：暗底上三行字幕，最下面一行被一块发光玻璃条盖住

func drawIcon(size S: CGFloat, into ctx: CGContext) {
    ctx.setFillColor(NSColor.clear.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

    let inset = S * 0.085
    let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = rect.width * 0.2237
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [0.09, 0.10, 0.16, 1])!,
        CGColor(colorSpace: cs, components: [0.05, 0.05, 0.08, 1])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // 画面里的一点光
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [1.0, 0.45, 0.62, 0.55])!,
        CGColor(colorSpace: cs, components: [0.30, 0.20, 0.55, 0.0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.26),
                           startRadius: 0,
                           endCenter: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.26),
                           endRadius: rect.width * 0.55, options: [])

    let glow2 = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [0.30, 0.85, 1.0, 0.45])!,
        CGColor(colorSpace: cs, components: [0.10, 0.30, 0.55, 0.0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow2,
                           startCenter: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.72),
                           startRadius: 0,
                           endCenter: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.72),
                           endRadius: rect.width * 0.42, options: [])

    // 两行「字幕」
    func textBar(_ y: CGFloat, _ w: CGFloat, alpha: CGFloat) {
        let h = rect.height * 0.055
        let r = CGRect(x: rect.midX - w / 2, y: y, width: w, height: h)
        ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, alpha])!)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.fillPath()
    }
    textBar(rect.minY + rect.height * 0.40, rect.width * 0.62, alpha: 0.85)
    textBar(rect.minY + rect.height * 0.28, rect.width * 0.46, alpha: 0.7)

    // 玻璃遮挡条
    let barH = rect.height * 0.20
    let bar = CGRect(x: rect.minX + rect.width * 0.10,
                     y: rect.minY + rect.height * 0.235,
                     width: rect.width * 0.80, height: barH)
    let barPath = CGPath(roundedRect: bar, cornerWidth: barH * 0.34, cornerHeight: barH * 0.34, transform: nil)

    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()
    let glass = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [0.92, 0.96, 1.0, 0.42])!,
        CGColor(colorSpace: cs, components: [0.55, 0.62, 0.85, 0.20])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: bar.minX, y: bar.maxY),
                           end: CGPoint(x: bar.minX, y: bar.minY), options: [])
    ctx.restoreGState()

    ctx.setLineWidth(max(1, S * 0.008))
    ctx.addPath(barPath)
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 0.75])!)
    ctx.strokePath()

    ctx.restoreGState()
}

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let dir = "/tmp/Kagemaku.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

for (pt, scale) in sizes {
    let px = pt * scale
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    drawIcon(size: CGFloat(px), into: ctx)
    guard let img = ctx.makeImage() else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    let rep = NSBitmapImageRep(cgImage: img)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    }
}
print("iconset -> \(dir)")
