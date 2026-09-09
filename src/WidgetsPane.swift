import AppKit
import SwiftUI

struct WidgetsPane: View {
    let app: AppDelegate
    @EnvironmentObject var store: Store

    private var maskIndex: Int? {
        if let id = store.activeMaskID, let i = store.masks.firstIndex(where: { $0.id == id }) { return i }
        return store.masks.isEmpty ? nil : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "显示部件",
                         note: "字幕挡住了，条身就空着。一条遮挡条只用一个装置主题，数字走一种管子，长文走另一种，字号按条身高度按比例算。")
            if let i = maskIndex {
                if store.masks.count > 1 { maskSwitcher(i) }
                themePicker(i)
                WidgetStrip(widgets: store.masks[i].widgets, themeID: store.masks[i].themeID)
                addBar(i)
                ForEach(store.masks[i].widgets) { w in
                    WidgetCard(app: app, maskIndex: i, widgetID: w.id)
                }
                if store.masks[i].widgets.isEmpty {
                    Text("这条上面还什么都没有，从上面挑一个加进去。")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.faint)
                }
            }
        }
    }

    private func maskSwitcher(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text("正在编辑")
                .font(.system(size: 11))
                .foregroundStyle(UI.faint)
            ForEach(Array(store.masks.enumerated()), id: \.element.id) { idx, m in
                let on = idx == i
                Text(m.label)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.black.opacity(0.85) : UI.dim)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(on ? UI.accent : Color.white.opacity(0.05)))
                    .contentShape(Rectangle())
                    .onTapGesture { store.activeMaskID = m.id }
            }
            Spacer()
        }
    }

    private func themePicker(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("装置主题")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(UI.dim)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                ForEach(DeviceTheme.all) { t in
                    ThemeCard(theme: t, selected: t.id == store.masks[i].themeID) {
                        store.masks[i].themeID = t.id
                        store.save()
                        app.refreshVisuals()
                    }
                }
            }
        }
    }

    private func addBar(_ i: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(WidgetKind.allCases) { k in
                GhostButton(title: k.label, symbol: k.symbol) {
                    store.masks[i].widgets.append(MaskWidget.make(k))
                    store.save()
                    app.refreshVisuals()
                    DataHub.shared.register(store.masks.flatMap { $0.widgets })
                }
            }
            Spacer()
        }
    }
}

struct ThemeCard: View {
    let theme: DeviceTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sample
            Text(theme.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(UI.text)
            Text(theme.note)
                .font(.system(size: 10.5))
                .foregroundStyle(UI.faint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? UI.panelHi : UI.panel)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? UI.accent.opacity(0.8) : UI.stroke,
                                  lineWidth: selected ? 1.4 : 1))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var sample: some View {
        HStack(spacing: 10) {
            numeric
            Spacer(minLength: 0)
            Circle().fill(theme.ink.color).frame(width: 8, height: 8)
            Circle().fill(theme.dim.color).frame(width: 8, height: 8)
            Circle().fill(theme.up.color).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.34)))
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
            FakeFrame()
            WidgetLayer(widgets: widgets, themeID: themeID, opacity: 1)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(UI.stroke, lineWidth: 1))
    }
}

struct WidgetCard: View {
    let app: AppDelegate
    let maskIndex: Int
    let widgetID: UUID
    @EnvironmentObject var store: Store

    private var idx: Int? {
        store.masks[maskIndex].widgets.firstIndex { $0.id == widgetID }
    }

    var body: some View {
        if let j = idx {
            let w = store.masks[maskIndex].widgets[j]
            Card {
                header(w, j)
                Divider().overlay(UI.stroke)
                Row(label: "位置") {
                    Segmented(items: [(0, "靠左"), (1, "居中"), (2, "靠右")], selection: bind(j, \.align))
                }
                Row(label: "层级", note: "主 0.30 倍条高，次 0.20，注 0.133，字号跟着条身走") {
                    Segmented(items: WidgetRole.allCases.map { ($0, $0.label) }, selection: bind(j, \.role))
                }
                if w.followTheme {
                    Row(label: "字号微调") {
                        NumberSlider(value: bind(j, \.scale), range: 0.7...1.4,
                                     format: { String(format: "%.2f×", $0) })
                    }
                }
                Row(label: "跟随装置主题", note: "关掉才自己挑管子和颜色，一条上混装置会散") {
                    Toggle("", isOn: bind(j, \.followTheme)).labelsHidden().tint(UI.accent)
                }
                if !w.followTheme {
                    Row(label: "样式") {
                        Menu(w.style.label) {
                            ForEach(WidgetStyle.allCases) { s in
                                Button(s.label) { set(j) { $0.style = s } }
                            }
                        }.menuStyle(.borderlessButton).fixedSize()
                    }
                    Row(label: "字号") {
                        NumberSlider(value: bind(j, \.size), range: 10...54, step: 1)
                    }
                    Row(label: "颜色") {
                        SwatchPicker(label: w.color.hexString, rgba: bind(j, \.color))
                    }
                }
                if w.kind != .text {
                    Row(label: "注记", note: "行情和天气不填就用代码和地名") {
                        PlainField(placeholder: "可留空", text: bind(j, \.label)).frame(width: 160)
                    }
                }
                if !w.kind.sourceHint.isEmpty {
                    Row(label: sourceLabel(w.kind), note: w.kind.sourceHint) {
                        PlainField(placeholder: w.kind.sourceHint, text: bind(j, \.source))
                            .frame(width: 260)
                    }
                }
                if w.kind == .clock || w.kind == .date {
                    Row(label: "格式", note: "HH:mm:ss / MM月dd日 这类写法，日期不写星期会自动补一个") {
                        PlainField(placeholder: "HH:mm:ss", text: bind(j, \.format)).frame(width: 180)
                    }
                }
                if w.kind == .quote {
                    Row(label: "带涨跌幅", note: "涨绿跌红是语义色，不算主题主色") {
                        Toggle("", isOn: bind(j, \.showChange)).labelsHidden().tint(UI.accent)
                    }
                }
                Row(label: "跑马灯", note: "长文本从右往左滚，新闻用得上") {
                    Toggle("", isOn: bind(j, \.marquee)).labelsHidden().tint(UI.accent)
                }
            }
        }
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

    private func header(_ w: MaskWidget, _ j: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: w.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(UI.accent)
            Text(w.kind.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.text)
            Text(w.role.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UI.dim)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            Spacer()
            Toggle("", isOn: bind(j, \.enabled)).labelsHidden().tint(UI.accent)
            GhostButton(title: "移除", symbol: "trash", tone: Color.white.opacity(0.12)) {
                store.masks[maskIndex].widgets.removeAll { $0.id == widgetID }
                store.save()
                app.refreshVisuals()
                DataHub.shared.register(store.masks.flatMap { $0.widgets })
            }
        }
    }

    private func set(_ j: Int, _ change: (inout MaskWidget) -> Void) {
        var w = store.masks[maskIndex].widgets[j]
        change(&w)
        store.masks[maskIndex].widgets[j] = w
        store.save()
        app.refreshVisuals()
        DataHub.shared.register(store.masks.flatMap { $0.widgets })
    }

    private func bind<V>(_ j: Int, _ path: WritableKeyPath<MaskWidget, V>) -> Binding<V> {
        Binding(
            get: { store.masks[maskIndex].widgets[j][keyPath: path] },
            set: { v in set(j) { $0[keyPath: path] = v } }
        )
    }
}
