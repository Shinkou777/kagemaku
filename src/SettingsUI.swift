import AppKit
import SwiftUI

// 设置窗用系统的分组表单，跟着系统深浅色走。这里放几处共用的行和预览画面。

// MARK: - 行

/// 标题、一句说明、滑块和读数
struct SliderRow: View {
    let title: String
    var note: String? = nil
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                slider.frame(width: 190)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(title)
            if let note { Text(note) }
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: value, in: range, step: step)
        } else {
            Slider(value: value, in: range)
        }
    }
}

/// 标题、一句说明和一个开关
struct ToggleRow: View {
    let title: String
    var note: String? = nil
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            Text(title)
            if let note { Text(note) }
        }
    }
}

/// 颜色和它的色号
struct ColorRow: View {
    let title: String
    @Binding var rgba: RGBA

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(rgba.hexString + (rgba.a < 0.995 ? "  \(Int((rgba.a * 100).rounded()))%" : ""))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: Binding(
                    get: { rgba.color },
                    set: { rgba = RGBA.from($0) }
                ), supportsOpacity: true)
                .labelsHidden()
            }
        }
    }
}

// MARK: - 删除前问一句

@MainActor
enum Confirm {
    /// 确认在右、取消在左
    static func ask(_ title: String, detail: String, action: String = "移除") -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        let ok = a.addButton(withTitle: action)
        ok.hasDestructiveAction = true
        a.addButton(withTitle: "取消")
        let app = NSApp.delegate as? AppDelegate
        app?.lowerPanels()
        defer { app?.restorePanels() }
        return a.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - 预览用的假画面

/// 一段渐变当画面，底下可以叠一行或两行字幕，用来看遮挡效果
struct FakeFrame: View {
    var compact: Bool = false
    var lines: [String] = ["この街の灯りは、ぜんぶ誰かの生活だ"]
    /// 给第一行盖上学外语那种透明玻璃，值是模糊半径
    var glassFirst: Double? = nil

    var body: some View {
        ZStack {
            scene
            VStack(spacing: compact ? 2 : 4) {
                Spacer()
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    if i == 0, let r = glassFirst {
                        glassLine(line, radius: r)
                    } else {
                        subtitle(line, big: i == 0 && lines.count > 1)
                    }
                }
            }
            .padding(.bottom, compact ? 12 : 22)
        }
    }

    private var scene: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.26),
                                    Color(red: 0.30, green: 0.20, blue: 0.34),
                                    Color(red: 0.62, green: 0.36, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: compact ? 40 : 110)
                .blur(radius: compact ? 12 : 30)
                .offset(x: compact ? 40 : 130, y: compact ? -18 : -40)
            Circle()
                .fill(Color(red: 0.4, green: 0.7, blue: 0.9).opacity(0.25))
                .frame(width: compact ? 30 : 90)
                .blur(radius: compact ? 10 : 24)
                .offset(x: compact ? -50 : -160, y: compact ? 8 : 20)
        }
    }

    private func subtitle(_ s: String, big: Bool) -> some View {
        Text(s)
            .font(.system(size: compact ? 9 : (big ? 19 : 15), weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 1.2)
            .shadow(color: .black.opacity(0.8), radius: 3)
    }

    /// 字糊掉，底下衬一条两端渐隐的淡玻璃，看得出玻璃盖到哪
    private func glassLine(_ s: String, radius: Double) -> some View {
        subtitle(s, big: true)
            .blur(radius: radius)
            .padding(.horizontal, 44)
            .padding(.vertical, 5)
            .background(
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.15),
                                                 .init(color: .black, location: 0.85),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
            )
    }
}

/// 学外语模式的样子：上面一行中文被糊掉，下面一行外文照常
struct LearnPreview: View {
    let strength: Double
    var zh = "这件事我们以后再说吧"
    var en = "Let's talk about it later."

    var body: some View {
        // 预览里中文 19 点，按真机的算法玻璃约 40 点高，半径取 0.2 倍再乘强度
        FakeFrame(lines: [zh, en], glassFirst: max(1.5, 40 * 0.2 * strength) * 0.45)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
