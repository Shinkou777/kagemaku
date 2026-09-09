import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case masks, widgets, skins, keys, tracking, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .masks: return "遮挡条"
        case .widgets: return "显示部件"
        case .skins: return "皮肤"
        case .keys: return "快捷键"
        case .tracking: return "追踪与检测"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .masks: return "rectangle.stack"
        case .widgets: return "gauge.with.dots.needle.bottom.50percent"
        case .skins: return "paintpalette"
        case .keys: return "keyboard"
        case .tracking: return "scope"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store
    @State private var pane: SettingsPane = .masks

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(UI.stroke)
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(UI.bg)
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(UI.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .masks: MasksPane(app: app)
        case .widgets: WidgetsPane(app: app)
        case .skins: SkinsPane(app: app)
        case .keys: KeysPane(app: app)
        case .tracking: TrackingPane(app: app)
        case .about: AboutPane()
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            brand
                .padding(.bottom, 14)
            ForEach(SettingsPane.allCases) { p in
                railItem(p)
            }
            Spacer()
            footer
        }
        .padding(14)
        .frame(width: 196)
        .background(Color.black.opacity(0.28))
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("影幕")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(UI.text)
            Text("Kagemaku")
                .font(.system(size: 10, weight: .medium))
                .tracking(2.6)
                .foregroundStyle(UI.faint)
        }
        .padding(.top, 18)
        .padding(.leading, 6)
    }

    private func railItem(_ p: SettingsPane) -> some View {
        let on = pane == p
        return HStack(spacing: 9) {
            Image(systemName: p.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            Text(p.title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
            Spacer()
        }
        .foregroundStyle(on ? UI.text : UI.dim)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on ? Color.white.opacity(0.08) : Color.clear)
                .overlay(alignment: .leading) {
                    if on {
                        Capsule().fill(UI.accent).frame(width: 2.5, height: 15)
                            .padding(.leading, 2)
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture { pane = p }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            GhostButton(title: "新建遮挡条", symbol: "plus") {
                app.addMask()
            }
            GhostButton(title: "全部显示", symbol: "eye") {
                for c in app.controllers { c.setHidden(false) }
            }
        }
    }
}

// MARK: - 遮挡条

struct MasksPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "遮挡条", note: "双语字幕就摆两条，各遮各的。位置直接在屏幕上拖，这里管属性。")
            ForEach(store.masks) { m in
                MaskCard(app: app, id: m.id)
            }
            GhostButton(title: "再加一条", symbol: "plus") { app.addMask() }
        }
    }
}

struct MaskCard: View {
    let app: AppDelegate
    let id: UUID
    @EnvironmentObject var store: Store

    private var index: Int? { store.masks.firstIndex { $0.id == id } }

    var body: some View {
        if let i = index {
            let m = store.masks[i]
            Card {
                header(m, i)
                Divider().overlay(UI.stroke)
                Row(label: "不透明度", note: "调到 30% 以下能隐约看见字幕轮廓，适合做提示") {
                    NumberSlider(value: bind(i, \.opacity), range: 0.05...1.0,
                                 format: { "\(Int($0 * 100))%" })
                }
                Row(label: "皮肤") {
                    skinPicker(i, m)
                }
                Row(label: "追踪", note: trackNote(m)) {
                    Segmented(items: TrackMode.allCases.map { ($0, $0.label) },
                              selection: bind(i, \.trackMode))
                }
                if m.trackMode == .window {
                    Row(label: "跟随哪个窗口") { windowPicker(i, m) }
                }
                Row(label: "位置") {
                    Text(rectText(m.frame))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(UI.faint)
                }
            }
            .onChange(of: store.masks[i]) { _, _ in
                app.refreshAll()
            }
        }
    }

    private func header(_ m: MaskConfig, _ i: Int) -> some View {
        HStack(spacing: 10) {
            PlainField(placeholder: "名称", text: bind(i, \.label))
                .frame(width: 150)
            Spacer()
            toggleChip(m.locked ? "已锁定" : "可拖动", symbol: m.locked ? "lock.fill" : "lock.open",
                       on: m.locked) {
                app.controller(id)?.setLocked(!m.locked)
            }
            toggleChip(m.hidden ? "已隐藏" : "显示中", symbol: m.hidden ? "eye.slash" : "eye",
                       on: m.hidden) {
                app.controller(id)?.setHidden(!m.hidden)
            }
            GhostButton(title: "移除", symbol: "trash", tone: Color.white.opacity(0.12)) {
                if let c = app.controller(id) { app.removeMask(c) }
            }
        }
    }

    private func toggleChip(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? UI.accent : UI.dim)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(on ? UI.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(Capsule().strokeBorder(on ? UI.accent.opacity(0.5) : UI.stroke, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func skinPicker(_ i: Int, _ m: MaskConfig) -> some View {
        Menu {
            ForEach(store.skins) { s in
                Button(s.name) { store.masks[i].skinID = s.id; store.save(); app.refreshAll() }
            }
        } label: {
            HStack(spacing: 6) {
                SkinChip(skin: store.skin(m.skinID))
                Text(store.skin(m.skinID).name).font(.system(size: 12)).foregroundStyle(UI.text)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(UI.faint)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func windowPicker(_ i: Int, _ m: MaskConfig) -> some View {
        Menu {
            ForEach(WindowTracker.list(excluding: [ProcessInfo.processInfo.processIdentifier])) { w in
                Button(w.display) {
                    app.controller(id)?.setTrackMode(.window, windowID: w.id, owner: w.owner)
                    if let cfg = app.controller(id)?.config { store.masks[i] = cfg }
                }
            }
        } label: {
            Text(m.trackWindowOwner ?? "选一个窗口")
                .font(.system(size: 12))
                .foregroundStyle(m.trackWindowOwner == nil ? UI.faint : UI.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func trackNote(_ m: MaskConfig) -> String {
        switch m.trackMode {
        case .manual: return "条固定在屏幕上，你拖到哪就在哪"
        case .window: return "按相对比例锚在播放器窗口里，窗口移动缩放都跟着走"
        case .subtitle: return "定时采样字幕区域，自动对齐到那一行，需要屏幕录制权限"
        }
    }

    private func rectText(_ r: CGRect) -> String {
        "x \(Int(r.minX))　y \(Int(r.minY))　\(Int(r.width))×\(Int(r.height))"
    }

    private func bind<V>(_ i: Int, _ path: WritableKeyPath<MaskConfig, V>) -> Binding<V> {
        Binding(
            get: { store.masks[i][keyPath: path] },
            set: { store.masks[i][keyPath: path] = $0; store.save() }
        )
    }
}

struct SkinChip: View {
    let skin: Skin

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [skin.tintTop.color, skin.tintBottom.color],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [skin.borderTop.color, skin.borderBottom.color],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
            .frame(width: 22, height: 14)
            .background(Color.white.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 4)))
    }
}
