import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case masks, learn, skins, widgets, keys, tracking, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .masks: return "遮挡条"
        case .learn: return "学外语"
        case .skins: return "皮肤"
        case .widgets: return "显示部件"
        case .keys: return "快捷键"
        case .tracking: return "追踪与检测"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .masks: return "rectangle.stack"
        case .learn: return "character.book.closed"
        case .skins: return "paintpalette"
        case .widgets: return "clock"
        case .keys: return "keyboard"
        case .tracking: return "scope"
        case .about: return "info.circle"
        }
    }
}

/// 设置窗现在停在哪一页；菜单和工具条可以直接跳过来
final class SettingsNav: ObservableObject {
    @Published var pane: SettingsPane = .masks
}

struct SettingsView: View {
    let app: AppDelegate
    @ObservedObject var nav: SettingsNav
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsPane?>(
                get: { nav.pane },
                set: { if let p = $0 { nav.pane = p } }
            )) {
                ForEach(SettingsPane.allCases) { p in
                    Label(p.title, systemImage: p.symbol).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            content
                .navigationTitle(nav.pane.title)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch nav.pane {
        case .masks: MasksPane(app: app)
        case .learn: LearnPane(app: app)
        case .skins: SkinsPane(app: app)
        case .widgets: WidgetsPane(app: app)
        case .keys: KeysPane(app: app)
        case .tracking: TrackingPane(app: app)
        case .about: AboutPane()
        }
    }
}

// MARK: - 遮挡条

struct MasksPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            if store.masks.isEmpty {
                Section {
                    Text("现在一条都没有。点下面的按钮，或者按 \(store.settings.hotkey(.newMask).display) 新建。")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(store.masks) { m in
                MaskSection(app: app, id: m.id)
            }
            Section {
                HStack {
                    Button("新建遮挡条") { app.addMask() }
                    Spacer()
                    if store.masks.contains(where: \.hidden) {
                        Button("全部显示") { for c in app.controllers { c.setHidden(false) } }
                    }
                }
            } footer: {
                Text("位置直接在屏幕上拖。双语字幕想分开处理，可以摆两条：一条练听力全挡住，一条学外语只盖中文。")
            }
        }
        .formStyle(.grouped)
    }
}

struct MaskSection: View {
    let app: AppDelegate
    let id: UUID
    @EnvironmentObject var store: Store

    private var mask: MaskConfig? { store.masks.first { $0.id == id } }
    private var controller: MaskController? { app.controller(id) }

    var body: some View {
        if let m = mask {
            Section {
                TextField("名称", text: bind(\.label))
                modeRow(m)
                trackRow(m)
                if m.trackMode == .window { windowRow(m) }
                if m.mode == .cover {
                    skinRow(m)
                    SliderRow(title: "不透明度", note: "调到 30% 以下能隐约看见字幕轮廓",
                              value: bind(\.opacity), range: 0.05...1.0,
                              format: { "\(Int(($0 * 100).rounded()))%" })
                }
                ToggleRow(title: "锁定", note: "鼠标穿过去，点得到底下的播放器",
                          isOn: Binding(get: { m.locked }, set: { controller?.setLocked($0) }))
                ToggleRow(title: "显示", isOn: Binding(get: { !m.hidden }, set: { controller?.setHidden(!$0) }))
                LabeledContent("位置") {
                    Text(rectText(m.frame)).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    Button("摆回屏幕中下方") { if let c = controller { app.resetPosition(c) } }
                    Spacer()
                    Button("移除这条…", role: .destructive) { if let c = controller { app.confirmRemove(c) } }
                }
            } header: {
                Text(m.label)
            }
        }
    }

    private func modeRow(_ m: MaskConfig) -> some View {
        Picker(selection: Binding(get: { m.mode }, set: { controller?.setMode($0) })) {
            ForEach(MaskMode.allCases) { Text($0.label).tag($0) }
        } label: {
            Text("用途")
            Text(m.mode.note)
        }
        .pickerStyle(.segmented)
    }

    private func trackRow(_ m: MaskConfig) -> some View {
        Picker(selection: Binding(get: { m.trackMode }, set: { setTrack($0) })) {
            Text("自动对齐字幕").tag(TrackMode.subtitle)
            Text(TrackMode.manual.label).tag(TrackMode.manual)
            Text(TrackMode.window.label).tag(TrackMode.window)
        } label: {
            Text("追踪")
            Text(trackNote(m))
        }
    }

    private func setTrack(_ t: TrackMode) {
        controller?.setTrackMode(t)
        app.restartDetectTimer()
    }

    private func windowRow(_ m: MaskConfig) -> some View {
        Picker("跟随哪个窗口", selection: Binding<UInt32>(
            get: { m.trackWindowID ?? 0 },
            set: { wid in
                guard let w = WindowTracker.list(excluding: [ProcessInfo.processInfo.processIdentifier]).first(where: { $0.id == wid }) else { return }
                controller?.setTrackMode(.window, windowID: w.id, owner: w.owner)
            })) {
            if m.trackWindowID == nil { Text("选一个窗口").tag(UInt32(0)) }
            ForEach(WindowTracker.list(excluding: [ProcessInfo.processInfo.processIdentifier])) { w in
                Text(w.display).tag(w.id)
            }
            if let wid = m.trackWindowID,
               !WindowTracker.list(excluding: [ProcessInfo.processInfo.processIdentifier]).contains(where: { $0.id == wid }) {
                Text((m.trackWindowOwner ?? "窗口") + "（已关闭）").tag(wid)
            }
        }
    }

    private func skinRow(_ m: MaskConfig) -> some View {
        Picker("皮肤", selection: Binding(get: { m.skinID }, set: { controller?.setSkin($0) })) {
            ForEach(store.skins) { s in Text(s.name).tag(s.id) }
        }
    }

    private func trackNote(_ m: MaskConfig) -> String {
        switch m.trackMode {
        case .manual: return "拖到哪就在哪"
        case .window: return "按比例锚在播放器窗口里，窗口挪动、缩放都跟着走"
        case .subtitle:
            return m.mode == .learn ? "认出中文那一行，玻璃上下边对过去，要屏幕录制权限"
                                    : "认出字幕在哪，条的上下边对过去，要屏幕录制权限"
        }
    }

    private func rectText(_ r: CGRect) -> String {
        "x \(Int(r.minX))　y \(Int(r.minY))　\(Int(r.width))×\(Int(r.height))"
    }

    /// 名称、不透明度这类只改存档和外观的
    private func bind<V>(_ path: WritableKeyPath<MaskConfig, V>) -> Binding<V> {
        Binding(
            get: { mask?[keyPath: path] ?? MaskConfig()[keyPath: path] },
            set: { v in
                guard let i = store.masks.firstIndex(where: { $0.id == id }) else { return }
                store.masks[i][keyPath: path] = v
                store.save()
                app.refreshVisuals()
            }
        )
    }
}

// MARK: - 学外语

struct LearnPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store
    @State private var permitted = SubtitleDetector.hasPermission

    private var learnCount: Int { store.masks.filter { $0.mode == .learn }.count }

    var body: some View {
        Form {
            Section {
                LearnPreview(strength: store.settings.learnBlur)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text("看双语字幕时，玻璃只糊掉中文那一行，外文照常看。看不懂了按住 \(store.settings.hotkey(.peek).display) 偷看中文。")
            }

            Section("这条玻璃") {
                SliderRow(title: "模糊强度", note: "中文还认得出就往右调，画面糊得太多就往左",
                          value: Binding(get: { store.settings.learnBlur },
                                         set: { store.settings.learnBlur = $0; store.save(); app.refreshVisuals() }),
                          range: 0.6...2.0, step: 0.05, format: { String(format: "%.2f×", $0) })
                LabeledContent("正在学外语的遮挡条") {
                    Text(learnCount == 0 ? "还没有" : "\(learnCount) 条").foregroundStyle(.secondary)
                }
                HStack {
                    Button(learnCount == 0 ? "把当前这条切到学外语" : "再加一条学外语") {
                        if learnCount == 0, let c = app.activeController {
                            c.setMode(.learn)
                        } else {
                            app.addMask()
                            app.activeController?.setMode(.learn)
                        }
                    }
                    Spacer()
                }
            }

            Section {
                LabeledContent("屏幕录制") {
                    Text(permitted ? "已经允许" : "还没允许").foregroundStyle(permitted ? Color.secondary : Color.orange)
                }
                HStack {
                    Button("打开系统设置") {
                        CGRequestScreenCaptureAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("重新检查") { permitted = SubtitleDetector.hasPermission }
                    Spacer()
                }
            } header: {
                Text("自动对齐要用的权限")
            } footer: {
                Text("影幕只拍玻璃附近那一小块画面，在本机认出哪一行是中文，画面不存、不上传。没允许的话玻璃照样能用，要自己拖到中文那一行上。允许之后系统会让影幕重开一次。")
            }

            Section("怎么认中文行") {
                Text("有汉字、没有假名的那一行算中文。中日双语时日文那行带假名，不会被盖住。")
                Text("中文在上、外文在下，或者反过来，都会找准两行之间的缝，玻璃的边停在外文字的外面。")
                Text("字幕偶尔变成两行，玻璃马上跟着变高；变回一行，过三秒才缩回去，免得句子换得快时露出来。")
                Text("第一次认字要加载识别模型，新装或刚更新时可能要等十几秒。")
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { permitted = SubtitleDetector.hasPermission }
    }
}
