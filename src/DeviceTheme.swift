import AppKit
import SwiftUI

// MARK: - 层级与比例尺

/// 字号不手写，按条身内高换算。三档之间是 1.5 的比例。
enum WidgetRole: String, Codable, CaseIterable, Identifiable {
    case primary, secondary, caption

    var id: String { rawValue }

    var label: String {
        switch self {
        case .primary: return "主"
        case .secondary: return "次"
        case .caption: return "注"
        }
    }

    var factor: CGFloat {
        switch self {
        case .primary: return 0.300
        case .secondary: return 0.200
        case .caption: return 0.133
        }
    }

    var bounds: ClosedRange<CGFloat> {
        switch self {
        case .primary: return 13...44
        case .secondary: return 10...30
        case .caption: return 8...20
        }
    }

    func size(in contentHeight: CGFloat, scale: Double) -> CGFloat {
        let raw = contentHeight * factor * CGFloat(scale)
        return min(max(raw, bounds.lowerBound), bounds.upperBound)
    }
}

// MARK: - 装置主题

/// 一条遮挡条只认一个显示家族：数字走 numeric，文字走 text。
/// 这样五个部件摆一起也是同一台仪器，不是五台。
struct DeviceTheme: Identifiable, Equatable {
    var id: String
    var name: String
    var note: String
    var numeric: WidgetStyle
    var text: WidgetStyle
    var ink: RGBA
    var dim: RGBA
    var up: RGBA
    var down: RGBA

    static let all: [DeviceTheme] = [departure, terminal, vacuum, plain]

    static func by(_ id: String) -> DeviceTheme {
        all.first { $0.id == id } ?? departure
    }

    /// 発車標：翻页牌报数字，点阵跑长文。中性灰往冷偏，主色只给主读数。
    static let departure = DeviceTheme(
        id: "departure",
        name: "発車標 Departure",
        note: "翻页牌报数字，长文走素字。车站候车厅那块牌子。",
        numeric: .splitflap,
        text: .plain,
        ink: RGBA(hex: "#F0F2F5"),
        dim: RGBA(hex: "#7C838F"),
        up: RGBA(hex: "#5FD08A"),
        down: RGBA(hex: "#FF7B72")
    )

    /// 端末：七段配点阵，磷光绿一色到底。
    static let terminal = DeviceTheme(
        id: "terminal",
        name: "端末 Terminal",
        note: "七段数码管配点阵，磷光绿一色到底。交易台。",
        numeric: .seg7,
        text: .dotmatrix,
        ink: RGBA(hex: "#63F1A0"),
        dim: RGBA(hex: "#4A8267"),
        up: RGBA(hex: "#7CFFB2"),
        down: RGBA(hex: "#FF8A80")
    )

    /// 真空管：辉光管报数字，长文用素字，暖琥珀。
    static let vacuum = DeviceTheme(
        id: "vacuum",
        name: "真空管 Vacuum",
        note: "辉光管报数字，长文走素字。深夜暖橙。",
        numeric: .nixie,
        text: .plain,
        ink: RGBA(hex: "#FFA24C"),
        dim: RGBA(hex: "#9A7250"),
        up: RGBA(hex: "#8FE0A6"),
        down: RGBA(hex: "#FF8F7A")
    )

    /// 無地：全素字，层级只靠大小和字重。
    static let plain = DeviceTheme(
        id: "plain",
        name: "無地 Plain",
        note: "不上装置，层级只靠字号和字重撑。",
        numeric: .plain,
        text: .plain,
        ink: RGBA(hex: "#EDEFF5"),
        dim: RGBA(hex: "#818894"),
        up: RGBA(hex: "#6FD79A"),
        down: RGBA(hex: "#FF8A82")
    )

    func style(for kind: WidgetKind) -> WidgetStyle {
        switch kind {
        case .clock, .date, .quote: return numeric
        case .weather, .news, .text: return text
        }
    }
}

// MARK: - 解出一个部件真正要用的参数

struct ResolvedWidget {
    var style: WidgetStyle
    var size: CGFloat
    var captionSize: CGFloat
    var ink: Color
    var dim: Color
    var up: Color
    var down: Color
}

enum WidgetResolver {
    static func resolve(_ w: MaskWidget, theme: DeviceTheme, contentHeight h: CGFloat) -> ResolvedWidget {
        let capSize = WidgetRole.caption.size(in: h, scale: 1)
        if w.followTheme {
            let size = w.role.size(in: h, scale: w.scale)
            var st = theme.style(for: w.kind)
            if st == .dotmatrix && size < 22 { st = .plain }
            return ResolvedWidget(
                style: st,
                size: size,
                captionSize: capSize,
                ink: theme.ink.color,
                dim: theme.dim.color,
                up: theme.up.color,
                down: theme.down.color)
        }
        return ResolvedWidget(
            style: w.style,
            size: CGFloat(w.size),
            captionSize: capSize,
            ink: w.color.color,
            dim: theme.dim.color,
            up: theme.up.color,
            down: theme.down.color)
    }
}
