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
                         note: "字幕挡住了，条身就空着。往上摆时间、行情、天气、新闻，样式有辉光管、翻页牌、点阵、数码管。")
            if let i = maskIndex {
                if store.masks.count > 1 { maskSwitcher(i) }
                WidgetStrip(widgets: store.masks[i].widgets)
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

/// 设置页里的整条预览
struct WidgetStrip: View {
    let widgets: [MaskWidget]

    var body: some View {
        ZStack {
            FakeFrame()
            WidgetLayer(widgets: widgets, opacity: 1)
        }
        .frame(height: 96)
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
                Row(label: "样式") {
                    Menu(w.style.label) {
                        ForEach(WidgetStyle.allCases) { s in
                            Button(s.label) { set(j) { $0.style = s } }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Row(label: "位置") {
                    Segmented(items: [(0, "靠左"), (1, "居中"), (2, "靠右")], selection: bind(j, \.align))
                }
                Row(label: "字号") {
                    NumberSlider(value: bind(j, \.size), range: 10...54, step: 1)
                }
                Row(label: "颜色") {
                    SwatchPicker(label: w.color.hexString, rgba: bind(j, \.color))
                }
                if w.kind != .text {
                    Row(label: "前缀名", note: "比如给日経挂个「日経」，留空就不显示") {
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
                    Row(label: "格式", note: "HH:mm:ss / MM月dd日(EEE) 这类写法") {
                        PlainField(placeholder: "HH:mm:ss", text: bind(j, \.format)).frame(width: 180)
                    }
                }
                if w.kind == .quote {
                    Row(label: "带涨跌幅") {
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
