import AppKit
import SwiftUI

struct SkinsPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store
    @State private var selected: UUID? = nil

    private var currentID: UUID {
        selected ?? app.activeController?.config.skinID ?? store.skins.first?.id ?? UUID()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "皮肤", note: "内置的七套可以直接用。想改就复制一份，改动只落在你自己的那份上。")
            gallery
            if let i = store.skins.firstIndex(where: { $0.id == currentID }) {
                SkinPreview(skin: store.skins[i], opacity: app.activeController?.config.opacity ?? 0.95)
                actions(i)
                SkinEditor(app: app, index: i)
            }
        }
    }

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
            ForEach(store.skins) { s in
                SkinTile(skin: s, selected: s.id == currentID) {
                    selected = s.id
                }
            }
        }
    }

    private func actions(_ i: Int) -> some View {
        let s = store.skins[i]
        return HStack(spacing: 8) {
            GhostButton(title: "用在当前遮挡条", symbol: "checkmark.circle") {
                app.activeController?.setSkin(s.id)
            }
            GhostButton(title: "复制一份来改", symbol: "doc.on.doc") {
                var copy = s
                copy.id = UUID()
                copy.builtIn = false
                copy.name = s.name + " 改"
                store.upsert(skin: copy)
                selected = copy.id
            }
            if !s.builtIn {
                GhostButton(title: "删除这套", symbol: "trash", tone: Color.white.opacity(0.12)) {
                    store.deleteSkin(s.id)
                    selected = store.skins.first?.id
                    app.refreshAll()
                }
            }
            Spacer()
            if s.builtIn {
                Text("内置皮肤只读，复制一份就能改")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.faint)
            }
        }
    }
}

struct SkinTile: View {
    let skin: Skin
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                FakeFrame(compact: true)
                SkinLayer(skin: skin, opacity: 0.95, reduceMotion: false, preview: true)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .offset(y: 14)
            }
            .frame(height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(spacing: 5) {
                Text(skin.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                if !skin.builtIn {
                    Text("自定义")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(UI.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(UI.accent.opacity(0.14)))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? UI.panelHi : UI.panel)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? UI.accent.opacity(0.8) : UI.stroke, lineWidth: selected ? 1.4 : 1))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 预览用的假画面：一段渐变加一行日文，用来看遮挡效果
struct FakeFrame: View {
    var compact: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.26),
                                    Color(red: 0.30, green: 0.20, blue: 0.34),
                                    Color(red: 0.62, green: 0.36, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: compact ? 40 : 90)
                .blur(radius: compact ? 12 : 26)
                .offset(x: compact ? 40 : 110, y: compact ? -18 : -40)
            VStack {
                Spacer()
                Text("この街の灯りは、ぜんぶ誰かの生活だ")
                    .font(.system(size: compact ? 9 : 15, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1.5)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .padding(.bottom, compact ? 14 : 26)
            }
        }
    }
}

struct SkinPreview: View {
    let skin: Skin
    let opacity: Double

    var body: some View {
        ZStack {
            FakeFrame()
            VStack {
                Spacer()
                SkinLayer(skin: skin, opacity: opacity, reduceMotion: false, preview: true)
                    .frame(height: 52)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
            }
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(UI.stroke, lineWidth: 1))
    }
}

struct SkinEditor: View {
    let app: AppDelegate
    let index: Int
    @EnvironmentObject var store: Store

    private var skin: Skin { store.skins[index] }
    private var locked: Bool { skin.builtIn }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                SectionTitle(text: "玻璃")
                Row(label: "名称") { PlainField(placeholder: "皮肤名", text: b(\.name)).frame(width: 200) }
                Row(label: "毛玻璃", note: "关掉就是纯色遮挡，彻底看不见底下") {
                    Toggle("", isOn: b(\.blur)).labelsHidden().tint(UI.accent)
                }
                Row(label: "材质") {
                    Menu(skin.material.label) {
                        ForEach(MaterialKind.allCases) { m in
                            Button(m.label) { set { $0.material = m } }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Row(label: "玻璃明暗") {
                    Segmented(items: AppearanceKind.allCases.map { ($0, $0.label) }, selection: b(\.appearance))
                }
                Row(label: "饱和度", note: "调高会把底下的画面搅成彩色雾") {
                    NumberSlider(value: b(\.blurSaturation), range: 0.0...2.5,
                                 format: { String(format: "%.2f", $0) })
                }
            }

            Card {
                SectionTitle(text: "底色")
                Row(label: "上端色") { SwatchPicker(label: skin.tintTop.hexString, rgba: b(\.tintTop)) }
                Row(label: "下端色") { SwatchPicker(label: skin.tintBottom.hexString, rgba: b(\.tintBottom)) }
                Row(label: "渐变角度") {
                    NumberSlider(value: b(\.gradientAngle), range: 0...360, step: 1,
                                 format: { "\(Int($0))°" })
                }
                Row(label: "顶部高光") {
                    NumberSlider(value: b(\.innerHighlight), range: 0...1,
                                 format: { String(format: "%.2f", $0) })
                }
            }

            Card {
                SectionTitle(text: "轮廓")
                Row(label: "圆角") { NumberSlider(value: b(\.cornerRadius), range: 0...40, step: 1) }
                Row(label: "描边粗细") {
                    NumberSlider(value: b(\.borderWidth), range: 0...5, step: 0.1,
                                 format: { String(format: "%.1f", $0) })
                }
                Row(label: "描边起色") { SwatchPicker(label: skin.borderTop.hexString, rgba: b(\.borderTop)) }
                Row(label: "描边止色") { SwatchPicker(label: skin.borderBottom.hexString, rgba: b(\.borderBottom)) }
                Row(label: "外发光半径") { NumberSlider(value: b(\.glowRadius), range: 0...60, step: 1) }
                Row(label: "发光颜色") { SwatchPicker(label: skin.glowColor.hexString, rgba: b(\.glowColor)) }
            }

            Card {
                SectionTitle(text: "动效")
                Row(label: "类型") {
                    Menu(skin.effect.label) {
                        ForEach(SkinEffect.allCases) { e in
                            Button(e.label) { set { $0.effect = e } }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Row(label: "动效颜色") { SwatchPicker(label: skin.effectColor.hexString, rgba: b(\.effectColor)) }
                Row(label: "强度") {
                    NumberSlider(value: b(\.effectIntensity), range: 0...1,
                                 format: { String(format: "%.2f", $0) })
                }
                Row(label: "速度") {
                    NumberSlider(value: b(\.effectSpeed), range: 0...3,
                                 format: { String(format: "%.2f", $0) })
                }
            }
        }
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
    }

    private func set(_ change: (inout Skin) -> Void) {
        var s = store.skins[index]
        change(&s)
        store.skins[index] = s
        store.save()
        app.refreshVisuals()
    }

    private func b<V>(_ path: WritableKeyPath<Skin, V>) -> Binding<V> {
        Binding(
            get: { store.skins[index][keyPath: path] },
            set: { v in set { $0[keyPath: path] = v } }
        )
    }
}
