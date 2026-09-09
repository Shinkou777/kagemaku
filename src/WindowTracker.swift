import AppKit
import CoreGraphics

struct TargetWindow: Identifiable, Equatable {
    var id: UInt32
    var owner: String
    var title: String
    var bounds: CGRect      // 已转换为 NSWindow 坐标系（原点左下）
    var pid: pid_t

    var display: String {
        title.isEmpty ? owner : "\(owner) — \(title)"
    }
}

enum WindowTracker {

    /// 主屏高度，用于 CG（左上原点）与 NS（左下原点）互转
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cgToNS(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// 列出可见的普通窗口。窗口标题需要「屏幕录制」权限才拿得到，
    /// 拿不到时退化成只显示 App 名，功能不受影响。
    static func list(excluding ownPIDs: Set<pid_t> = []) -> [TargetWindow] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [TargetWindow] = []
        for w in raw {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = w[kCGWindowNumber as String] as? UInt32,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { continue }
            let pid = (w[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            if ownPIDs.contains(pid) { continue }
            if rect.width < 200 || rect.height < 140 { continue }
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? "未知"
            let title = (w[kCGWindowName as String] as? String) ?? ""
            out.append(TargetWindow(id: num, owner: owner, title: title,
                                    bounds: cgToNS(rect), pid: pid))
        }
        // 面积大的排前面，播放器窗口通常最大
        return out.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    }

    static func bounds(of id: UInt32) -> CGRect? {
        guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let w = raw.first,
              let dict = w[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
        else { return nil }
        if rect.width < 2 || rect.height < 2 { return nil }
        return cgToNS(rect)
    }

    static func exists(_ id: UInt32) -> Bool {
        bounds(of: id) != nil
    }
}
