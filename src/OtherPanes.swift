import AppKit
import SwiftUI

// MARK: - 快捷键

struct KeysPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                ToggleRow(title: "启用全局快捷键", note: "播放器在前台也拦得住",
                          isOn: Binding(
                            get: { store.settings.hotkeysEnabled },
                            set: { store.settings.hotkeysEnabled = $0; store.save(); app.registerHotkeys() }))
            }
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    LabeledContent {
                        KeyRecorder(spec: specBinding(action)) { s in
                            store.settings.hotkeys[action.rawValue] = s
                            store.save()
                            app.registerHotkeys()
                        }
                        .frame(width: 118, height: 24)
                    } label: {
                        Text(action.label)
                        Text(action.note)
                    }
                }
            } footer: {
                Text("点方框，再按新的组合键就改好了；按 esc 取消。")
            }
            .disabled(!store.settings.hotkeysEnabled)

            Section("偷看") {
                Picker("方式", selection: Binding(
                    get: { store.settings.peekHold },
                    set: { store.settings.peekHold = $0; store.save() })) {
                    Text("按住时看").tag(true)
                    Text("按一下切换").tag(false)
                }
                .pickerStyle(.segmented)
                SliderRow(title: "偷看时留多少玻璃", note: "留一点雾比全透明好认，眼睛不会被字晃到",
                          value: Binding(
                            get: { store.settings.peekOpacity },
                            set: { store.settings.peekOpacity = $0; store.save(); app.refreshVisuals() }),
                          range: 0...0.6, format: { "\(Int(($0 * 100).rounded()))%" })
            }
        }
        .formStyle(.grouped)
    }

    private func specBinding(_ a: HotkeyAction) -> Binding<HotkeySpec> {
        Binding(
            get: { store.settings.hotkey(a) },
            set: { store.settings.hotkeys[a.rawValue] = $0; store.save() }
        )
    }
}

// MARK: - 追踪与检测

struct TrackingPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                SliderRow(title: "搜索范围", note: "以玻璃为中心上下一共看多高。窄一点省电，也不容易被画面里别的字带跑",
                          value: bind(\.detectBand), range: 100...420, step: 10, format: { "\(Int($0)) 点" })
                SliderRow(title: "每秒看几次", note: "认字比较费电，两次够用",
                          value: bind(\.detectRateHz), range: 1...4, step: 0.5, format: { String(format: "%.1f", $0) })
                SliderRow(title: "听力模式上下留白", note: "整条挡住时，在字幕外面多盖出去的边",
                          value: bind(\.detectPadding), range: 0...40, step: 1, format: { "\(Int($0)) 点" })
            } header: {
                Text("自动对齐字幕")
            } footer: {
                Text("影幕定时拍下玻璃附近那块画面，在本机认出字幕所在的行，把玻璃的上下边对过去。要屏幕录制权限，画面不存、不上传。")
            }

            Section("行为") {
                ToggleRow(title: "浮在全屏视频之上", note: "关掉的话，全屏播放时遮挡条会被盖住",
                          isOn: Binding(
                            get: { store.settings.aboveFullscreen },
                            set: { store.settings.aboveFullscreen = $0; store.save(); app.refreshAll() }))
                ToggleRow(title: "贴边吸附", note: "拖到屏幕边缘或水平中线附近会自动对齐",
                          isOn: Binding(
                            get: { store.settings.snapEdges },
                            set: { store.settings.snapEdges = $0; store.save(); app.refreshAll() }))
                ToggleRow(title: "关掉动效", note: "流光、扫描线、极光全部静止，省电",
                          isOn: Binding(
                            get: { store.settings.reduceMotion },
                            set: { store.settings.reduceMotion = $0; store.save(); app.refreshVisuals() }))
            }

            Section {
                WindowList()
            } header: {
                Text("跟随播放器窗口")
            } footer: {
                Text("遮挡条按比例锚在选中的窗口里，窗口挪动、缩放、切到别的桌面都跟着走。这个不要权限，拿不到窗口标题时只显示 App 名。")
            }
        }
        .formStyle(.grouped)
    }

    private func bind(_ path: WritableKeyPath<GlobalSettings, Double>) -> Binding<Double> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: { store.settings[keyPath: path] = $0; store.save(); app.restartDetectTimer() }
        )
    }
}

struct WindowList: View {
    @State private var windows: [TargetWindow] = []

    var body: some View {
        Group {
            if windows.isEmpty {
                Text("还没找到窗口").foregroundStyle(.secondary)
            } else {
                ForEach(windows.prefix(8)) { w in
                    LabeledContent(w.display) {
                        Text("\(Int(w.bounds.width))×\(Int(w.bounds.height))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            }
            HStack {
                Spacer()
                Button("刷新") { reload() }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        windows = WindowTracker.list(excluding: [ProcessInfo.processInfo.processIdentifier])
    }
}

// MARK: - 关于

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("影幕 Kagemaku").font(.system(size: 18, weight: .semibold))
                    Text("挡住字幕先听，听不出来再偷看一眼；学外语时只盖中文。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("版本", value: version)
                LabeledContent("数据") {
                    Text("~/Library/Application Support/Kagemaku/")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section("用法") {
                Text("拖条身移动，拖四边和四角缩放，鼠标停上去出工具条。")
                Text("锁定之后鼠标穿过去，播放器的进度条照点，用快捷键或菜单栏解锁。")
                Text("学外语：右键选「学外语：只盖中文」，玻璃变透明，只糊中文那一行。")
                Text("换番也不用重摆：选「跟随播放器窗口」，位置按比例记住。")
                Text("要退出，右键遮挡条或者点菜单栏图标，选「退出影幕」。")
            }
            .foregroundStyle(.secondary)
            Section {
                Link("GitHub · Shinkou777/kagemaku", destination: URL(string: "https://github.com/Shinkou777/kagemaku")!)
                Link("ShinkoUniv", destination: URL(string: "https://shinkouniv.com")!)
            }
        }
        .formStyle(.grouped)
    }
}
