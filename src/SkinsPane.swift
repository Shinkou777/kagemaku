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
        Form {
            Section {
                gallery
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } footer: {
                Text("皮肤只管练听力那种整条挡住的遮挡条；学外语用固定的透明玻璃，强度在「学外语」里调。")
            }
            if let i = store.skins.firstIndex(where: { $0.id == currentID }) {
                let s = store.skins[i]
                Section {
                    SkinPreview(skin: s, opacity: app.activeController?.config.opacity ?? 0.95)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    actions(s)
                } header: {
                    Text(s.name)
                } footer: {
                    if s.builtIn { Text("内置皮肤不能改，复制一份就能改，改动只落在你那份上。") }
                }
                if !s.builtIn {
                    SkinEditor(app: app, id: s.id)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(store.skins) { s in
                SkinTile(skin: s, selected: s.id == currentID) {
                    selected = s.id
                }
            }
        }
    }

    private func actions(_ s: Skin) -> some View {
        let using = app.activeController?.config.skinID == s.id
        return HStack(spacing: 8) {
            Button(using ? "当前遮挡条正在用" : "用在当前遮挡条") {
                app.activeController?.setSkin(s.id)
            }
            .disabled(using || app.activeController == nil)
            Button("复制一份来改") {
                var copy = s
                copy.id = UUID()
                copy.builtIn = false
                copy.name = s.name + " 改"
                store.upsert(skin: copy)
                selected = copy.id
            }
            Spacer()
            if !s.builtIn {
                Button("删除这套…", role: .destructive) {
                    guard Confirm.ask("删除皮肤「\(s.name)」？",
                                      detail: "删掉就找不回来了。正在用它的遮挡条会换回第一套内置皮肤。",
                                      action: "删除") else { return }
                    store.deleteSkin(s.id)
                    selected = store.skins.first?.id
                    app.refreshAll()
                }
            }
        }
    }
}

struct SkinTile: View {
    let skin: Skin
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                FakeFrame(compact: true)
                SkinLayer(skin: skin, opacity: 0.95, reduceMotion: true, preview: true)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .offset(y: 14)
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            HStack(spacing: 4) {
                Text(skin.name)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if !skin.builtIn {
                    Text("自己的").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
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
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SkinEditor: View {
    let app: AppDelegate
    let id: UUID
    @EnvironmentObject var store: Store

    private var skin: Skin { store.skins.first { $0.id == id } ?? SkinPresets.frosted }

    var body: some View {
        Section("名称") {
            TextField("皮肤名", text: b(\.name))
        }
        glass
        tint
        outline
        motion
    }

    private var glass: some View {
        Section("玻璃") {
            ToggleRow(title: "毛玻璃", note: "关掉就是纯色，彻底看不见底下", isOn: b(\.blur))
            if skin.blur {
                Picker("材质", selection: b(\.material)) {
                    ForEach(MaterialKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("玻璃明暗", selection: b(\.appearance)) {
                    ForEach(AppearanceKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                ToggleRow(title: "只留模糊", note: "去掉系统叠在玻璃上的灰和提亮，画面颜色不变", isOn: b(\.pureBlur))
                SliderRow(title: "模糊半径", note: "0 用材质自带的", value: b(\.blurRadius), range: 0...40, step: 1,
                          format: { $0 < 0.5 ? "自带" : "\(Int($0))" })
                SliderRow(title: "饱和度", note: "调高会把底下的画面搅成彩色雾", value: b(\.blurSaturation),
                          range: 0...2.5, format: { String(format: "%.2f", $0) })
                SliderRow(title: "两端羽化", note: "0 是硬边圆角", value: b(\.feather), range: 0...40, step: 1)
            }
        }
    }

    private var tint: some View {
        Section("底色") {
            ColorRow(title: "上端色", rgba: b(\.tintTop))
            ColorRow(title: "下端色", rgba: b(\.tintBottom))
            SliderRow(title: "渐变角度", value: b(\.gradientAngle), range: 0...360, step: 1, format: { "\(Int($0))°" })
            SliderRow(title: "顶部高光", value: b(\.innerHighlight), range: 0...1, format: { String(format: "%.2f", $0) })
        }
    }

    private var outline: some View {
        Section("轮廓") {
            SliderRow(title: "圆角", value: b(\.cornerRadius), range: 0...40, step: 1)
            SliderRow(title: "描边粗细", value: b(\.borderWidth), range: 0...5, step: 0.1, format: { String(format: "%.1f", $0) })
            ColorRow(title: "描边起色", rgba: b(\.borderTop))
            ColorRow(title: "描边止色", rgba: b(\.borderBottom))
            SliderRow(title: "外发光半径", value: b(\.glowRadius), range: 0...Skin.maxGlow, step: 1)
            ColorRow(title: "发光颜色", rgba: b(\.glowColor))
        }
    }

    private var motion: some View {
        Section {
            Picker("类型", selection: b(\.effect)) {
                ForEach(SkinEffect.allCases) { Text($0.label).tag($0) }
            }
            if skin.effect != .none {
                ColorRow(title: "动效颜色", rgba: b(\.effectColor))
                SliderRow(title: "强度", value: b(\.effectIntensity), range: 0...1, format: { String(format: "%.2f", $0) })
                SliderRow(title: "速度", value: b(\.effectSpeed), range: 0...3, format: { String(format: "%.2f", $0) })
            }
        } header: {
            Text("动效")
        } footer: {
            Text("盖在字幕上的东西一直在动会分心，用不着就选「无」。")
        }
    }

    private func b<V>(_ path: WritableKeyPath<Skin, V>) -> Binding<V> {
        Binding(
            get: { skin[keyPath: path] },
            set: { v in
                guard let i = store.skins.firstIndex(where: { $0.id == id }) else { return }
                store.skins[i][keyPath: path] = v
                store.save()
                app.refreshVisuals()
            }
        )
    }
}
