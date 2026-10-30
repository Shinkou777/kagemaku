import AppKit
import ScreenCaptureKit
import CoreGraphics
import Vision

/// 在遮挡条附近的搜索带里采样屏幕，认出每一行字和它是中文还是外文，
/// 交给 SubtitleLayout 决定玻璃摆在哪。需要「屏幕录制」权限。
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

    /// 第一次认字要加载识别模型，新机器上可能要十几秒
    private(set) var warmedUp = false
    var lastError: String?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

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
    ///   - excluding: 自家面板的 windowNumber，拍的时候把自己去掉，才看得见玻璃底下的字
    /// - Returns: 认出来的行，屏幕坐标；正在忙就返回 nil
    func read(band: CGRect, excluding ownWindowNumbers: Set<CGWindowID>) async throws -> [TextLine]? {
        if busy { return nil }
        busy = true
        defer { busy = false }

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(band) }) ?? NSScreen.main else {
            throw DetectError.noDisplay
        }
        let clipped = band.intersection(screen.frame)
        guard clipped.width > 40, clipped.height > 20 else { return [] }

        guard let numberValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw DetectError.noDisplay
        }
        let displayID = CGDirectDisplayID(numberValue.uint32Value)

        let content: SCShareableContent
        do {
            content = try await shareableContent()
        } catch {
            lastError = error.localizedDescription
            throw Self.hasPermission ? DetectError.captureFailed : DetectError.noPermission
        }
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

        // 一点一像素就够认字幕；带子窄的时候放大一点，小字认得更稳
        let scale = min(2.0, max(1.0, 900.0 / Double(local.width)))
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = local
        cfg.width = max(16, Int(Double(local.width) * scale))
        cfg.height = max(16, Int(Double(local.height) * scale))
        cfg.showsCursor = false
        cfg.captureResolution = .best
        cfg.scalesToFit = true

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            lastError = error.localizedDescription
            throw Self.hasPermission ? DetectError.captureFailed : DetectError.noPermission
        }

        let lines = await Task.detached(priority: .userInitiated) {
            SubtitleOCR.lines(in: image, band: clipped)
        }.value
        warmedUp = true
        return lines
    }
}

// MARK: - 认字

enum SubtitleOCR {

    /// 图像里的每一行字，换成屏幕坐标。band 是这张图在屏幕上对应的矩形。
    static func lines(in image: CGImage, band: CGRect) -> [TextLine] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = false
        req.minimumTextHeight = 0.03
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        } catch {
            return []
        }
        guard let results = req.results, !results.isEmpty, let gray = GrayImage(image) else { return [] }

        let W = CGFloat(image.width), H = CGFloat(image.height)
        let sx = band.width / W, sy = band.height / H
        var out: [TextLine] = []
        for o in results {
            guard let text = o.topCandidates(1).first?.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let b = o.boundingBox
            // Vision 的框是归一化、原点左下；换成像素行（0 = 顶）
            let x0 = Int(b.minX * W), x1 = Int(b.maxX * W)
            let top = Int((1 - b.maxY) * H), bottom = Int((1 - b.minY) * H) - 1
            let ink = Ink.rows(in: gray, x0: x0, x1: x1, top: top, bottom: max(top, bottom))

            func screenRect(top: Int, bottom: Int) -> CGRect {
                CGRect(x: band.minX + CGFloat(x0) * sx,
                       y: band.maxY - CGFloat(bottom + 1) * sy,
                       width: CGFloat(x1 - x0) * sx,
                       height: CGFloat(bottom - top + 1) * sy)
            }
            out.append(TextLine(text: text,
                                kind: Script.kind(of: text),
                                ink: screenRect(top: ink.top, bottom: ink.bottom),
                                box: screenRect(top: top, bottom: max(top, bottom))))
        }
        return out
    }
}
