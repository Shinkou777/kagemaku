import AppKit
import SwiftUI

// MARK: - 快捷键

struct KeysPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "快捷键", note: "全局生效，播放器在前台也拦得住。点方框再按新的组合就改掉了。")
            Card {
                Row(label: "启用全局快捷键") {
                    Toggle("", isOn: Binding(
                        get: { store.settings.hotkeysEnabled },
                        set: { store.settings.hotkeysEnabled = $0; store.save(); app.registerHotkeys() }
                    )).labelsHidden().tint(UI.accent)
                }
                Divider().overlay(UI.stroke)
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { _, action in
                    Row(label: action.label, note: action.note) {
                        KeyRecorder(spec: specBinding(action)) { s in
                            store.settings.hotkeys[action.rawValue] = s
                            store.save()
                            app.registerHotkeys()
                        }
                        .frame(width: 122, height: 26)
                    }
                }
            }
            Card {
                SectionTitle(text: "偷看的方式")
                Row(label: "按住还是切换") {
                    Segmented(items: [(true, "按住时透明"), (false, "按一下切换")],
                              selection: Binding(
                                get: { store.settings.peekHold },
                                set: { store.settings.peekHold = $0; store.save() }))
                }
                Row(label: "偷看时的不透明度", note: "留一点点雾比全透明更好认，眼睛不会被字晃到") {
                    NumberSlider(value: Binding(
                        get: { store.settings.peekOpacity },
                        set: { store.settings.peekOpacity = $0; store.save(); app.refreshVisuals() }),
                                 range: 0...0.6, format: { "\(Int($0 * 100))%" })
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "追踪与检测")

            Card {
                SectionTitle(text: "自动吸附字幕")
                Text("影幕会在遮挡条附近开一条搜索带，定时采样这块画面，用横向梯度找出成行的文字，然后把条对齐过去。第一次开会弹屏幕录制授权。")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Row(label: "搜索带高度", note: "以遮挡条中心为准上下各扩一半。带越窄越省电，也越不容易跟丢") {
                    NumberSlider(value: bind(\.detectBand), range: 60...420, step: 10,
                                 format: { "\(Int($0)) pt" })
                }
                Row(label: "灵敏度", note: "调低更容易吸住细字，也更容易被画面纹理骗走") {
                    NumberSlider(value: bind(\.detectSensitivity), range: 0.2...0.85,
                                 format: { String(format: "%.2f", $0) })
                }
                Row(label: "采样频率") {
                    NumberSlider(value: bind(\.detectRateHz), range: 1...8, step: 0.5,
                                 format: { String(format: "%.1f Hz", $0) })
                }
                Row(label: "上下留白", note: "对齐后在文字行外多盖出去的边") {
                    NumberSlider(value: bind(\.detectPadding), range: 0...40, step: 1,
                                 format: { "\(Int($0)) pt" })
                }
                HStack {
                    GhostButton(title: "打开屏幕录制设置", symbol: "hand.raised") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer()
                }
            }

            Card {
                SectionTitle(text: "行为")
                Row(label: "浮在全屏视频之上", note: "关掉的话遮挡条只在普通窗口上层，全屏播放时会被盖住") {
                    Toggle("", isOn: Binding(
                        get: { store.settings.aboveFullscreen },
                        set: { store.settings.aboveFullscreen = $0; store.save(); app.refreshAll() }
                    )).labelsHidden().tint(UI.accent)
                }
                Row(label: "贴边吸附", note: "拖到屏幕边缘或水平中线附近会自动对齐") {
                    Toggle("", isOn: Binding(
                        get: { store.settings.snapEdges },
                        set: { store.settings.snapEdges = $0; store.save(); app.refreshAll() }
                    )).labelsHidden().tint(UI.accent)
                }
                Row(label: "关掉动效", note: "流光、扫描线、极光全部静止，省电") {
                    Toggle("", isOn: Binding(
                        get: { store.settings.reduceMotion },
                        set: { store.settings.reduceMotion = $0; store.save(); app.refreshVisuals() }
                    )).labelsHidden().tint(UI.accent)
                }
            }

            Card {
                SectionTitle(text: "跟随播放器窗口")
                Text("影幕按相对比例把遮挡条锚在你选的窗口里，窗口移动、缩放、切到别的桌面都跟着走。这条不需要任何权限；窗口标题拿不到时只会显示 App 名。")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.faint)
                    .fixedSize(horizontal: false, vertical: true)
                WindowList()
            }
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("当前可跟随的窗口")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(UI.dim)
                Spacer()
                GhostButton(title: "刷新", symbol: "arrow.clockwise") { reload() }
            }
            if windows.isEmpty {
                Text("还没扫到窗口，点一下刷新")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.faint)
            } else {
                ForEach(Array(windows.prefix(8).enumerated()), id: \.element.id) { i, w in
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(UI.faint)
                            .frame(width: 14, alignment: .trailing)
                        Text(w.display)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(w.bounds.width))×\(Int(w.bounds.height))")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(UI.faint)
                    }
                }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "关于")
            Card {
                Text("影幕 Kagemaku")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(UI.text)
                Text("挡住字幕先听，听不出来再偷看一眼。")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.dim)
                Divider().overlay(UI.stroke)
                VStack(alignment: .leading, spacing: 7) {
                    tip("1", "拖条身移动，拖四边和四角缩放，鼠标停上去出工具条。")
                    tip("2", "锁定之后鼠标穿透，播放器的进度条照点不误，用快捷键解锁。")
                    tip("3", "双语字幕摆两条，一条遮中文一条留日文。")
                    tip("4", "换台或者换番，用「跟随播放器窗口」，位置比例记住了就不用重摆。")
                }
                Divider().overlay(UI.stroke)
                Text("数据都在本地：~/Library/Application Support/Kagemaku/")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(UI.faint)
            }
        }
    }

    private func tip(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(UI.accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(UI.accent.opacity(0.14)))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(UI.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
