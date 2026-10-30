import CoreGraphics
import Foundation

// 字幕识别之后的排位逻辑：哪行是中文、字迹实际占多高、玻璃该摆在哪。
// 这里只做计算，不碰屏幕和窗口，tools/layout-test.swift 拿样本图直接跑。

// MARK: - 一行字

struct TextLine {
    enum Kind { case chinese, foreign, other }

    var text: String
    var kind: Kind
    /// 字迹实际占的范围，屏幕坐标（点，原点左下）
    var ink: CGRect
    /// Vision 给的框，屏幕坐标。上下比字迹松，相邻两行的框经常贴在一起
    var box: CGRect
}

enum Script {
    /// 有汉字、没有假名和谚文的算中文；日文句子几乎总带假名，所以中日双语里日文那行不会被当成中文。
    static func kind(of s: String) -> TextLine.Kind {
        var han = 0, kana = 0, hangul = 0, latin = 0
        for u in s.unicodeScalars {
            switch u.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: kana += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: han += 1
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: hangul += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: latin += 1
            default: break
            }
        }
        if han > 0 && kana == 0 && hangul == 0 && han >= latin { return .chinese }
        if han + kana + hangul + latin > 0 { return .foreign }
        return .other
    }
}

// MARK: - 灰度图

struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 4, h > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        width = w
        height = h
        pixels = buf
    }

    /// 每一行在 x0..<x1 之间的平均横向梯度。字幕是亮字加暗描边，字迹所在的行梯度高，行与行之间的缝低
    func rowEnergy(x0: Int, x1: Int, y0: Int, y1: Int) -> [Double] {
        let xa = max(1, x0), xb = min(width, x1)
        guard xb - xa > 2, y1 >= y0 else { return [] }
        var out = [Double](repeating: 0, count: y1 - y0 + 1)
        for y in y0...y1 {
            let row = y * width
            var sum = 0
            for x in xa..<xb {
                sum += abs(Int(pixels[row + x]) - Int(pixels[row + x - 1]))
            }
            out[y - y0] = Double(sum) / Double(xb - xa)
        }
        return out
    }
}

enum Ink {
    /// 在 Vision 框上下各放宽四分之一，从框中线往外走，能量掉到阈值以下就停。
    /// 输入输出都是图像像素行（0 = 顶）。
    static func rows(in g: GrayImage, x0: Int, x1: Int, top: Int, bottom: Int) -> (top: Int, bottom: Int) {
        let h = max(1, bottom - top + 1)
        let ext = max(2, h / 4)
        let ya = max(0, top - ext), yb = min(g.height - 1, bottom + ext)
        let raw = g.rowEnergy(x0: x0, x1: x1, y0: ya, y1: yb)
        guard raw.count > 4 else { return (top, bottom) }
        var e = raw
        for i in 1..<(raw.count - 1) { e[i] = (raw[i - 1] + raw[i] * 2 + raw[i + 1]) / 4 }

        let i0 = max(0, top - ya), i1 = min(e.count - 1, bottom - ya)
        let peak = e[i0...i1].max() ?? 0
        let floor = e.min() ?? 0
        guard peak - floor > 2 else { return (top, bottom) }
        let thr = floor + (peak - floor) * 0.18
        let gapAllow = max(1, h / 12)

        // 从框中间能量最高的那行往两边走
        let mid = (i0 + i1) / 2
        var seed = mid
        for i in i0...i1 where e[i] > e[seed] && abs(i - mid) < h / 3 { seed = i }

        var up = seed, gap = 0, i = seed
        while i > 0 {
            i -= 1
            if e[i] >= thr { up = i; gap = 0 } else { gap += 1; if gap > gapAllow { break } }
        }
        var down = seed
        gap = 0; i = seed
        while i < e.count - 1 {
            i += 1
            if e[i] >= thr { down = i; gap = 0 } else { gap += 1; if gap > gapAllow { break } }
        }
        return (ya + up, ya + down)
    }
}

// MARK: - 挑出要盖的那块

struct SubtitlePick {
    /// 要盖住的字迹范围
    var cover: CGRect
    /// 行高，按它算留白
    var lineHeight: CGFloat
    /// 同一块字幕里不能碰的行（学外语时的外文行）
    var guards: [CGRect]
}

enum SubtitleLayout {

    /// 上下挨着、左右有重叠的行归成一块字幕
    static func clusters(_ lines: [TextLine]) -> [[TextLine]] {
        let sorted = lines.sorted { $0.ink.midY > $1.ink.midY }
        var out: [[TextLine]] = []
        for l in sorted {
            if var last = out.last, let prev = last.last {
                let gap = prev.ink.minY - l.ink.maxY
                let lh = max(prev.ink.height, l.ink.height)
                let overlapX = min(prev.ink.maxX, l.ink.maxX) - max(prev.ink.minX, l.ink.minX)
                if gap < lh * 0.9 && overlapX > -lh {
                    last.append(l)
                    out[out.count - 1] = last
                    continue
                }
            }
            out.append([l])
        }
        return out
    }

    /// - Parameters:
    ///   - bar: 现在玻璃的位置
    ///   - loose: 刚拖过一下，第一次对齐不限距离
    static func pick(_ lines: [TextLine], mode: MaskMode, near bar: CGRect, loose: Bool) -> SubtitlePick? {
        let spanX = bar.insetBy(dx: -bar.width * 0.15, dy: 0)
        let usable = lines.filter {
            $0.kind != .other && $0.ink.height > 6
                && min($0.ink.maxX, spanX.maxX) - max($0.ink.minX, spanX.minX) > $0.ink.width * 0.5
        }
        var candidates: [SubtitlePick] = []
        for cl in clusters(usable) {
            switch mode {
            case .cover:
                let u = cl.map(\.ink).reduce(CGRect.null) { $0.union($1) }
                candidates.append(SubtitlePick(cover: u, lineHeight: cl.map(\.ink.height).max() ?? 0, guards: []))
            case .learn:
                // 一块里连着的中文行算一组，同块的外文行都是不能碰的
                let guards = cl.filter { $0.kind == .foreign }.map(\.ink)
                var run: [TextLine] = []
                func flush() {
                    guard !run.isEmpty else { return }
                    let u = run.map(\.ink).reduce(CGRect.null) { $0.union($1) }
                    candidates.append(SubtitlePick(cover: u, lineHeight: run.map(\.ink.height).max() ?? 0, guards: guards))
                    run = []
                }
                for l in cl {
                    if l.kind == .chinese { run.append(l) } else { flush() }
                }
                flush()
            }
        }
        func distance(_ r: CGRect) -> CGFloat {
            if r.maxY < bar.minY { return bar.minY - r.maxY }
            if r.minY > bar.maxY { return r.minY - bar.maxY }
            return 0
        }
        guard let best = candidates.min(by: { distance($0.cover) < distance($1.cover) }) else { return nil }
        if !loose && distance(best.cover) > max(best.lineHeight * 1.5, 24) { return nil }
        return best
    }
}

// MARK: - 记几秒的历史再定位置

/// 字幕一行两行来回变、偶尔一帧没认出来，玻璃都不该跟着抖。
/// 最近几秒认到的范围取并集：变大马上跟，变小等旧的过期。
final class SnapTracker {
    private var history: [(Date, SubtitlePick)] = []
    var span: TimeInterval = 3

    func reset() { history.removeAll() }

    func add(_ p: SubtitlePick, at t: Date = Date()) {
        history.append((t, p))
        history.removeAll { t.timeIntervalSince($0.0) > span }
    }

    var isEmpty: Bool { history.isEmpty }

    /// - Parameters:
    ///   - baseX: 用户自己摆的左右范围，学外语时只往外扩、不往里缩
    ///   - padding: 听力模式上下多盖出去的边
    ///   - featherX/featherY: 玻璃边缘羽化的宽度，字迹要落在羽化以内的实心区
    func target(mode: MaskMode, baseX: ClosedRange<CGFloat>, padding: CGFloat,
                featherX: CGFloat, featherY: CGFloat, now: Date = Date()) -> CGRect? {
        let recent = history.filter { now.timeIntervalSince($0.0) <= span }.map(\.1)
        guard !recent.isEmpty else { return nil }
        let cov = recent.map(\.cover).reduce(CGRect.null) { $0.union($1) }
        let lh = recent.map(\.lineHeight).max() ?? cov.height

        switch mode {
        case .cover:
            let top = cov.maxY + padding
            let bottom = cov.minY - padding
            return CGRect(x: baseX.lowerBound, y: bottom,
                          width: baseX.upperBound - baseX.lowerBound, height: top - bottom)

        case .learn:
            let pad = lh * 0.35 + featherY
            var top = cov.maxY + pad
            var bottom = cov.minY - pad
            let guards = recent.flatMap(\.guards).filter {
                min($0.maxX, cov.maxX) - max($0.minX, cov.minX) > 0
            }
            for g in guards {
                if g.midY < cov.midY {
                    // 外文在下：玻璃下沿停在外文字顶上面一点
                    var limit = g.maxY + 1.5
                    if limit > cov.minY - 1 { limit = (g.maxY + cov.minY) / 2 }
                    bottom = max(bottom, limit)
                } else {
                    var limit = g.minY - 1.5
                    if limit < cov.maxY + 1 { limit = (g.minY + cov.maxY) / 2 }
                    top = min(top, limit)
                }
            }
            let side = lh * 0.6 + featherX
            let left = min(baseX.lowerBound, cov.minX - side)
            let right = max(baseX.upperBound, cov.maxX + side)
            guard top - bottom > 6 else { return nil }
            return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        }
    }
}
