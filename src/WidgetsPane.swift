import AppKit
import SwiftUI

struct WidgetsPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    private var maskID: UUID? {
        if let id = store.activeMaskID, store.masks.contains(where: { $0.id == id }) { return id }
        return store.masks.first?.id
    }

    private var mask: MaskConfig? { maskID.flatMap { id in store.masks.first { $0.id == id } } }

    var body: some View {
        Form {
            if let m = mask {
                head(m)
                ForEach(m.widgets) { w in
                    WidgetSection(app: app, maskID: m.id, widgetID: w.id)
                }
            } else {
                Section { Text("先新建一条遮挡条。").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func head(_ m: MaskConfig) -> some View {
        Section {
            if store.masks.count > 1 {
                Picker("给哪一条", selection: Binding(get: { m.id }, set: { store.activeMaskID = $0 })) {
                    ForEach(store.masks) { Text($0.label).tag($0.id) }
                }
            }
            if m.mode == .learn {
                Text("这条现在是学外语，玻璃上不显示部件。切回听力就能看见。")
                    .foregroundStyle(.secondary)
            }
            WidgetStrip(widgets: m.widgets, themeID: m.themeID)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            HStack {
                Menu("添加部件") {
                    ForEach(WidgetKind.allCases) { k in
                        Button(k.label) { add(m.id, [MaskWidget.make(k)]) }
                    }
                }
                .fixedSize()
                if m.widgets.isEmpty {
                    Button("摆上一组示例") { add(m.id, MaskWidget.defaultSet) }
                }
                Spacer()
            }
        } footer: {
            Text("练听力时条身空着，可以叠点东西看：时间、行情、天气、新闻。默认什么都不放，盖在画面上一直跳动的字会分心。")
        }

        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(DeviceTheme.all) { t in
                    ThemeCard(theme: t, selected: t.id == m.themeID) {
                        update(m.id) { $0.themeID = t.id }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        } header: {
            Text("装置主题")
        } footer: {
            Text("一条只用一种装置：数字走一种管子，长文走另一种，字号按条身高度算。")
        }
    }

    private func add(_ id: UUID, _ list: [MaskWidget]) {
        update(id) { $0.widgets.append(contentsOf: list) }
    }

    private func update(_ id: UUID, _ change: (inout MaskConfig) -> Void) {
        guard let i = store.masks.firstIndex(where: { $0.id == id }) else { return }
        change(&store.masks[i])
        store.save()
        app.refreshVisuals()
    }
}

struct ThemeCard: View {
    let theme: DeviceTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sample
            Text(theme.name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
            Text(theme.note)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var sample: some View {
        HStack(spacing: 8) {
            numeric
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.09)))
    }

    @ViewBuilder
    private var numeric: some View {
        let c = theme.ink.color
        switch theme.numeric {
        case .nixie: NixieView(text: "12:34", size: 15, color: c)
        case .splitflap: SplitFlapView(text: "12:34", size: 15, color: c)
        case .seg7: Seg7View(text: "12:34", size: 16, color: c)
        case .dotmatrix: DotMatrixView(text: "12:34", size: 14, color: c)
        case .neon: NeonTextView(text: "12:34", size: 16, color: c)
        case .plain: PlainTextView(text: "12:34", size: 16, color: c)
        }
    }
}

/// 设置页里的整条预览
struct WidgetStrip: View {
    let widgets: [MaskWidget]
    let themeID: String

    var body: some View {
        ZStack {
            FakeFrame(lines: [])
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            if widgets.isEmpty {
                Text("条身空着")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                WidgetLayer(widgets: widgets, themeID: themeID, opacity: 1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct WidgetSection: View {
    let app: AppDelegate
    let maskID: UUID
    let widgetID: UUID
    @EnvironmentObject var store: Store

    private var widget: MaskWidget? {
        store.masks.first { $0.id == maskID }?.widgets.first { $0.id == widgetID }
    }

    var body: some View {
        if let w = widget {
            Section {
                Toggle("显示", isOn: bind(\.enabled))
                Picker("位置", selection: bind(\.align)) {
                    Text("靠左").tag(0); Text("居中").tag(1); Text("靠右").tag(2)
                }
                .pickerStyle(.segmented)
                Picker(selection: bind(\.role)) {
                    ForEach(WidgetRole.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("层级")
                    Text("主是条高的 0.30，次 0.20，注 0.133")
                }
                .pickerStyle(.segmented)
                if w.followTheme {
                    SliderRow(title: "字号微调", value: bind(\.scale), range: 0.7...1.4,
                              format: { String(format: "%.2f×", $0) })
                }
                ToggleRow(title: "跟随装置主题", note: "关掉才能自己挑管子和颜色", isOn: bind(\.followTheme))
                if !w.followTheme {
                    Picker("样式", selection: bind(\.style)) {
                        ForEach(WidgetStyle.allCases) { Text($0.label).tag($0) }
                    }
                    SliderRow(title: "字号", value: bind(\.size), range: 10...54, step: 1)
                    ColorRow(title: "颜色", rgba: bind(\.color))
                }
                content(w)
                ToggleRow(title: "跑马灯", note: "长文本从右往左滚", isOn: bind(\.marquee))
                HStack {
                    Spacer()
                    Button("移除这个部件…", role: .destructive) { remove(w) }
                }
            } header: {
                Label(w.kind.label, systemImage: w.kind.symbol)
            }
        }
    }

    @ViewBuilder
    private func content(_ w: MaskWidget) -> some View {
        if w.kind != .text {
            TextField(text: bind(\.label), prompt: Text("可留空")) {
                Text("注记")
                Text("行情和天气不填就用代码和地名")
            }
        }
        if !w.kind.sourceHint.isEmpty {
            TextField(text: bind(\.source), prompt: Text(w.kind.sourceHint)) {
                Text(sourceLabel(w.kind))
            }
        }
        if w.kind == .clock || w.kind == .date {
            TextField(text: bind(\.format), prompt: Text(w.kind == .clock ? "HH:mm:ss" : "MM/dd")) {
                Text("格式")
                Text("HH:mm:ss、MM月dd日 这类写法，日期不写星期会自动补")
            }
        }
        if w.kind == .quote {
            ToggleRow(title: "带涨跌幅", isOn: bind(\.showChange))
        }
    }

    private func remove(_ w: MaskWidget) {
        guard Confirm.ask("移除「\(w.kind.label)」部件？", detail: "这个部件的设置会一起删掉。") else { return }
        guard let i = store.masks.firstIndex(where: { $0.id == maskID }) else { return }
        store.masks[i].widgets.removeAll { $0.id == widgetID }
        store.save()
        app.refreshVisuals()
    }

    private func sourceLabel(_ k: WidgetKind) -> String {
        switch k {
        case .quote: return "代码"
        case .weather: return "城市"
        case .news: return "订阅源"
        case .text: return "文字"
        default: return "内容"
        }
    }

    private func bind<V>(_ path: WritableKeyPath<MaskWidget, V>) -> Binding<V> {
        Binding(
            get: { widget?[keyPath: path] ?? MaskWidget()[keyPath: path] },
            set: { v in
                guard let i = store.masks.firstIndex(where: { $0.id == maskID }),
                      let j = store.masks[i].widgets.firstIndex(where: { $0.id == widgetID }) else { return }
                store.masks[i].widgets[j][keyPath: path] = v
                store.save()
                app.refreshVisuals()
            }
        )
    }
}
