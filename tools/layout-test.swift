import AppKit
import CoreImage

// 拿样本图跑一遍认字和排位，出一张标了框、模拟了玻璃的图。
// 编：cp tools/layout-test.swift /tmp/main.swift && swiftc -O src/MaskMode.swift src/SubtitleLayout.swift src/SubtitleDetector.swift /tmp/main.swift -o /tmp/layout-test
// 跑：/tmp/layout-test <输出目录> <样本.png>...（样本按 2 倍图算，下 40% 当搜索带）

let args = CommandLine.arguments
let outDir = args[1]
var failures = 0

for path in args.dropFirst(2) {
    guard let ns = NSImage(contentsOfFile: path) else { print("读不了 \(path)"); continue }
    var r = CGRect(origin: .zero, size: ns.size)
    guard let full = ns.cgImage(forProposedRect: &r, context: nil, hints: nil) else { continue }
    let cropTop = full.height > 1000 ? Int(Double(full.height) * 0.6) : 0
    let img = full.cropping(to: CGRect(x: 0, y: cropTop, width: full.width, height: full.height - cropTop))!
    let band = CGRect(x: 0, y: 0, width: CGFloat(img.width) / 2, height: CGFloat(img.height) / 2)

    let t0 = Date()
    let lines = SubtitleOCR.lines(in: img, band: band)
    print("\n\((path as NSString).lastPathComponent)  \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    for l in lines.sorted(by: { $0.ink.midY > $1.ink.midY }) {
        print(String(format: "  %@  ink y %.1f–%.1f  box y %.1f–%.1f  %@",
                     "\(l.kind)".padding(toLength: 7, withPad: " ", startingAt: 0),
                     l.ink.minY, l.ink.maxY, l.box.minY, l.box.maxY, l.text))
    }

    // 玻璃一开始随便摆在带子中间，第一次不限距离
    let bar = CGRect(x: band.width * 0.2, y: band.midY - 20, width: band.width * 0.6, height: 40)
    let tracker = SnapTracker()
    guard let pick = SubtitleLayout.pick(lines, mode: .learn, near: bar, loose: true) else {
        print("  没有中文行"); continue
    }
    tracker.add(pick)
    guard let t = tracker.target(mode: .learn, baseX: bar.minX...bar.maxX, padding: 14, featherX: 22, featherY: 3) else {
        print("  算不出位置"); continue
    }
    print(String(format: "  玻璃 y %.1f–%.1f  x %.1f–%.1f", t.minY, t.maxY, t.minX, t.maxX))
    // 检查：中文字迹在玻璃实心区里，外文字迹不碰玻璃
    let solid = t.insetBy(dx: 0, dy: 3)
    for l in lines {
        if l.kind == .chinese && abs(l.ink.midY - pick.cover.midY) < pick.cover.height {
            let ok = solid.minY <= l.ink.minY + 0.5 && solid.maxY >= l.ink.maxY - 0.5
            print("  中文在实心区内：\(ok ? "是" : "否")"); if !ok { failures += 1 }
        }
        if l.kind == .foreign && min(l.ink.maxX, t.maxX) > max(l.ink.minX, t.minX) {
            let clear = l.ink.maxY <= t.minY || l.ink.minY >= t.maxY
            print("  外文「\(l.text.prefix(16))」没被盖：\(clear ? "是" : "否")"); if !clear { failures += 1 }
        }
    }

    // 出图：模拟玻璃（只在 t 里做高斯模糊）+ 标框
    let ci = CIImage(cgImage: img)
    let px = { (rr: CGRect) -> CGRect in CGRect(x: rr.minX * 2, y: rr.minY * 2, width: rr.width * 2, height: rr.height * 2) }
    let radius = Double(min(30, max(4, t.height * 0.2))) * 2
    let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: radius / 2).cropped(to: px(t))
    let composed = blurred.composited(over: ci)
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(composed, from: ci.extent) else { continue }
    let rep = NSBitmapImageRep(cgImage: cg)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for l in lines {
        (l.kind == .chinese ? NSColor.systemRed : NSColor.systemGreen).setStroke()
        let p = NSBezierPath(rect: px(l.ink)); p.lineWidth = 2; p.stroke()
    }
    NSColor.systemYellow.setStroke()
    let g = NSBezierPath(rect: px(t)); g.lineWidth = 3; g.setLineDash([10, 6], count: 2, phase: 0); g.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let out = (outDir as NSString).appendingPathComponent("lt-" + (path as NSString).lastPathComponent)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
}
print("\n不合格 \(failures) 处")
exit(failures == 0 ? 0 : 1)
