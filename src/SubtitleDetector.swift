import AppKit
import ScreenCaptureKit
import CoreGraphics

/// 在遮挡条附近的搜索带里采样屏幕，用水平梯度找出「文字行」，
/// 把遮挡条对齐到那一行。需要「屏幕录制」权限。
@MainActor
final class SubtitleDetector {

    enum DetectError: Error {
        case noPermission
        case noDisplay
        case captureFailed
    }

    private var contentCache: SCShareableContent?
    private var contentStamp: Date = .distantPast
    private var busy = false

    var lastError: String?

    func shareableContent() async throws -> SCShareableContent {
        if let c = contentCache, Date().timeIntervalSince(contentStamp) < 2.0 { return c }
        let c = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        contentCache = c
        contentStamp = Date()
        return c
    }

    func invalidate() {
        contentCache = nil
        contentStamp = .distantPast
    }

    /// - Parameters:
    ///   - band: 搜索带（NSWindow 坐标系，原点左下）
    ///   - excluding: 自家面板的 windowNumber，避免拍到自己
    /// - Returns: 检测到的字幕行在屏幕上的 y 范围（y 下沿, 高度）
    func detect(band: CGRect,
                excluding ownWindowNumbers: Set<CGWindowID>,
                sensitivity: Double) async throws -> ClosedRange<CGFloat>? {
        if busy { return nil }
        busy = true
        defer { busy = false }

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(band) }) ?? NSScreen.main else {
            throw DetectError.noDisplay
        }
        let clipped = band.intersection(screen.frame)
        guard clipped.width > 40, clipped.height > 20 else { return nil }

        guard let numberValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw DetectError.noDisplay
        }
        let displayID = CGDirectDisplayID(numberValue.uint32Value)

        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw DetectError.noDisplay
        }

        let ours = content.windows.filter { ownWindowNumbers.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: ours)

        // display 局部坐标：原点左上
        let local = CGRect(x: clipped.minX - screen.frame.minX,
                           y: screen.frame.maxY - clipped.maxY,
                           width: clipped.width,
                           height: clipped.height)

        let targetW = min(360.0, Double(local.width))
        let scale = targetW / Double(local.width)

        let cfg = SCStreamConfiguration()
        cfg.sourceRect = local
        cfg.width = max(16, Int(Double(local.width) * scale))
        cfg.height = max(16, Int(Double(local.height) * scale))
        cfg.showsCursor = false
        cfg.captureResolution = .nominal
        cfg.scalesToFit = true

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            lastError = error.localizedDescription
            throw DetectError.noPermission
        }

        guard let run = Self.textRun(in: image, sensitivity: sensitivity) else { return nil }

        let h = CGFloat(image.height)
        let topY = clipped.maxY - CGFloat(run.lowerBound) / h * clipped.height
        let bottomY = clipped.maxY - CGFloat(run.upperBound + 1) / h * clipped.height
        guard topY > bottomY else { return nil }
        return bottomY...topY
    }

    // MARK: 行分析

    /// 返回图像里最可能是字幕的连续行区间（图像坐标，0 = 顶）
    static func textRun(in image: CGImage, sensitivity: Double) -> ClosedRange<Int>? {
        let w = image.width, h = image.height
        guard w > 8, h > 8 else { return nil }

        var buf = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var scores = [Double](repeating: 0, count: h)
        for y in 0..<h {
            let row = y * w
            var sum = 0.0
            var x = 1
            while x < w {
                let d = Int(buf[row + x]) - Int(buf[row + x - 1])
                sum += Double(abs(d))
                x += 1
            }
            scores[y] = sum / Double(w - 1)
        }

        // 轻度平滑，压掉单行噪声
        var smooth = scores
        for y in 1..<(h - 1) {
            smooth[y] = (scores[y - 1] + scores[y] * 2 + scores[y + 1]) / 4
        }

        let maxS = smooth.max() ?? 0
        guard maxS > 6 else { return nil }              // 整条带都很平 → 没字
        let threshold = maxS * max(0.2, min(0.85, sensitivity))

        var runs: [(Int, Int, Double)] = []
        var start: Int? = nil
        var gap = 0
        var energy = 0.0
        for y in 0..<h {
            if smooth[y] >= threshold {
                if start == nil { start = y; energy = 0 }
                energy += smooth[y]
                gap = 0
            } else if let s = start {
                gap += 1
                if gap > max(2, h / 40) {
                    runs.append((s, y - gap, energy))
                    start = nil
                    gap = 0
                }
            }
        }
        if let s = start { runs.append((s, h - 1, energy)) }

        let minH = max(4, h / 30)
        let maxH = max(minH + 2, h * 2 / 3)
        let usable = runs.filter { ($0.1 - $0.0 + 1) >= minH && ($0.1 - $0.0 + 1) <= maxH }
        guard let best = usable.max(by: { $0.2 < $1.2 }) else { return nil }
        return best.0...best.1
    }
}
