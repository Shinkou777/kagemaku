import AppKit
import SwiftUI

// MARK: - 配色

enum UI {
    static let bg = Color(red: 0.043, green: 0.047, blue: 0.063)
    static let panel = Color(red: 0.078, green: 0.086, blue: 0.110)
    static let panelHi = Color(red: 0.106, green: 0.118, blue: 0.149)
    static let stroke = Color.white.opacity(0.09)
    static let strokeHi = Color.white.opacity(0.18)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.34)
    static let accent = Color(red: 0.43, green: 0.90, blue: 1.0)
    static let accent2 = Color(red: 1.0, green: 0.30, blue: 0.62)
}

// MARK: - 基础组件

struct SectionTitle: View {
    let text: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(UI.dim)
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(UI.faint)
            }
        }
        .padding(.bottom, 2)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(UI.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(UI.stroke, lineWidth: 1)
                )
        )
    }
}

struct Row<Control: View>: View {
    let label: String
    var note: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(UI.text)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

struct NumberSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step)
                .frame(width: 168)
                .tint(UI.accent)
            Text(format(value.wrappedValue))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(UI.dim)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct Segmented<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.0) { item in
                segment(item.0, item.1)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(UI.stroke, lineWidth: 1))
        )
    }

    private func segment(_ v: T, _ title: String) -> some View {
        let on = selection == v
        return Text(title)
            .font(.system(size: 12, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Color.black.opacity(0.85) : UI.dim)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? UI.accent : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { selection = v }
    }
}

struct GhostButton: View {
    let title: String
    var symbol: String? = nil
    var tone: Color = UI.strokeHi
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hover ? UI.text : UI.dim)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hover ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tone, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PlainField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(UI.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(UI.stroke, lineWidth: 1))
            )
    }
}

struct SwatchPicker: View {
    let label: String
    @Binding var rgba: RGBA

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { rgba.color },
                set: { rgba = RGBA.from($0) }
            ), supportsOpacity: true)
            .labelsHidden()
            .frame(width: 42)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(UI.faint)
        }
    }
}
