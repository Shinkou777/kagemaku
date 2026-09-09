import AppKit
import SwiftUI

// MARK: - 部件模型

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, date, quote, weather, news, text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clock: return "时间"
        case .date: return "日期"
        case .quote: return "行情"
        case .weather: return "天气"
        case .news: return "新闻"
        case .text: return "自定义文字"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .quote: return "chart.line.uptrend.xyaxis"
        case .weather: return "cloud.sun"
        case .news: return "newspaper"
        case .text: return "textformat"
        }
    }

    var sourceHint: String {
        switch self {
        case .quote: return "代码：^N225 / AAPL / BTC-USD / USDJPY=X / GC=F"
        case .weather: return "城市名：Tokyo / Osaka / 上海"
        case .news: return "RSS 地址"
        case .text: return "要显示的文字"
        default: return ""
        }
    }
}

enum WidgetStyle: String, Codable, CaseIterable, Identifiable {
    case nixie, splitflap, dotmatrix, seg7, neon, plain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nixie: return "辉光管"
        case .splitflap: return "翻页牌"
        case .dotmatrix: return "点阵"
        case .seg7: return "数码管"
        case .neon: return "霓虹"
        case .plain: return "简约"
        }
    }

    /// 只认得数字和少量符号的样式
    var digitsOnly: Bool { self == .seg7 }
}

struct MaskWidget: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: WidgetKind = .clock
    var style: WidgetStyle = .nixie
    var align: Int = 2              // 0 左 1 中 2 右
    var size: Double = 24
    var color: RGBA = RGBA(hex: "#FF9A3C")
    var enabled: Bool = true
    var label: String = ""          // 前缀，比如「日経」
    var source: String = ""         // 代码 / 城市 / RSS 地址 / 文字
    var format: String = ""         // 时间日期格式
    var marquee: Bool = false
    var showChange: Bool = true

    static func make(_ kind: WidgetKind) -> MaskWidget {
        var w = MaskWidget()
        w.kind = kind
        switch kind {
        case .clock:
            w.style = .nixie; w.align = 2; w.size = 26
            w.color = RGBA(hex: "#FF9A3C"); w.format = "HH:mm:ss"
        case .date:
            w.style = .splitflap; w.align = 0; w.size = 18
            w.color = RGBA(hex: "#EDEFF5"); w.format = "MM/dd EEE"
        case .quote:
            w.style = .seg7; w.align = 0; w.size = 20
            w.color = RGBA(hex: "#5CFF9D"); w.label = "日経"; w.source = "^N225"
        case .weather:
            w.style = .dotmatrix; w.align = 1; w.size = 18
            w.color = RGBA(hex: "#7ADFFF"); w.source = "Tokyo"
        case .news:
            w.style = .dotmatrix; w.align = 1; w.size = 16
            w.color = RGBA(hex: "#FFD166"); w.marquee = true
            w.source = "https://www3.nhk.or.jp/rss/news/cat0.xml"
        case .text:
            w.style = .neon; w.align = 1; w.size = 20
            w.color = RGBA(hex: "#FF4FA3"); w.source = "聴き取れるまで、開けない"
        }
        return w
    }

    /// 开箱就有东西看：左边日期加行情，中间新闻滚，右边天气加时间
    static var defaultSet: [MaskWidget] {
        var date = make(.date)
        date.align = 0; date.style = .splitflap; date.size = 16
        date.format = "MM/dd EEE"; date.color = RGBA(hex: "#EDEFF5")

        var quote = make(.quote)
        quote.align = 0; quote.style = .seg7; quote.size = 17
        quote.label = "日経"; quote.source = "^N225"; quote.color = RGBA(hex: "#5CFF9D")

        var news = make(.news)
        news.align = 1; news.style = .dotmatrix; news.size = 15
        news.marquee = true; news.color = RGBA(hex: "#FFC24C")

        var weather = make(.weather)
        weather.align = 2; weather.style = .plain; weather.size = 15
        weather.source = "Tokyo"; weather.color = RGBA(hex: "#9FE8FF")

        var clock = make(.clock)
        clock.align = 2; clock.style = .nixie; clock.size = 24
        clock.color = RGBA(hex: "#FFA24C")

        return [date, quote, news, weather, clock]
    }
}

// MARK: - 数据源

@MainActor
final class DataHub: ObservableObject {
    static let shared = DataHub()

    struct Quote: Equatable {
        var symbol: String
        var price: Double
        var changePct: Double
        var currency: String
    }

    struct WeatherNow: Equatable {
        var place: String
        var temp: Double
        var code: Int
    }

    @Published var quotes: [String: Quote] = [:]
    @Published var weather: [String: WeatherNow] = [:]
    @Published var headlines: [String: [String]] = [:]
    @Published var note: String = ""

    private var symbols: Set<String> = []
    private var cities: Set<String> = []
    private var feeds: Set<String> = []
    private var coords: [String: (Double, Double, String)] = [:]
    private var timer: Timer?
    private var running = false

    private init() {}

    func register(_ widgets: [MaskWidget]) {
        var s: Set<String> = [], c: Set<String> = [], f: Set<String> = []
        for w in widgets where w.enabled {
            let src = w.source.trimmingCharacters(in: .whitespaces)
            guard !src.isEmpty else { continue }
            switch w.kind {
            case .quote: s.insert(src)
            case .weather: c.insert(src)
            case .news: f.insert(src)
            default: break
            }
        }
        let changed = (s != symbols || c != cities || f != feeds)
        symbols = s; cities = c; feeds = f
        if changed || !running { start() }
    }

    func start() {
        running = true
        timer?.invalidate()
        Task { await refresh() }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var lastSlow: Date = .distantPast

    func refresh() async {
        for s in symbols {
            if let q = try? await Self.fetchQuote(s) { quotes[s] = q }
        }
        // 天气和新闻不用每分钟拉
        if Date().timeIntervalSince(lastSlow) > 600 {
            lastSlow = Date()
            for c in cities {
                if let w = try? await fetchWeather(c) { weather[c] = w }
            }
            for f in feeds {
                if let h = try? await Self.fetchFeed(f), !h.isEmpty { headlines[f] = h }
            }
        }
    }

    // MARK: 行情（Yahoo Finance 公开接口）

    static func fetchQuote(_ symbol: String) async throws -> Quote {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=2d") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any]
        else { throw URLError(.cannotParseResponse) }
        let price = (meta["regularMarketPrice"] as? Double) ?? 0
        let prev = (meta["chartPreviousClose"] as? Double)
            ?? (meta["previousClose"] as? Double) ?? price
        let cur = (meta["currency"] as? String) ?? ""
        let pct = (meta["regularMarketChangePercent"] as? Double)
            ?? (prev > 0 ? (price - prev) / prev * 100 : 0)
        return Quote(symbol: symbol, price: price, changePct: pct, currency: cur)
    }

    // MARK: 天气（Open-Meteo，无需 key）

    func fetchWeather(_ city: String) async throws -> WeatherNow {
        var lat = 0.0, lon = 0.0, name = city
        if let c = coords[city] {
            lat = c.0; lon = c.1; name = c.2
        } else {
            let q = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
            guard let gu = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1&language=ja") else {
                throw URLError(.badURL)
            }
            let (gd, _) = try await URLSession.shared.data(from: gu)
            guard let groot = try JSONSerialization.jsonObject(with: gd) as? [String: Any],
                  let arr = groot["results"] as? [[String: Any]], let first = arr.first,
                  let la = first["latitude"] as? Double, let lo = first["longitude"] as? Double
            else { throw URLError(.cannotParseResponse) }
            lat = la; lon = lo
            name = (first["name"] as? String) ?? city
            coords[city] = (lat, lon, name)
        }
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = root["current"] as? [String: Any],
              let t = cur["temperature_2m"] as? Double
        else { throw URLError(.cannotParseResponse) }
        let code = (cur["weather_code"] as? Int) ?? 0
        return WeatherNow(place: name, temp: t, code: code)
    }

    static func weatherWord(_ code: Int) -> String {
        switch code {
        case 0: return "快晴"
        case 1: return "晴"
        case 2: return "薄曇"
        case 3: return "曇"
        case 45, 48: return "霧"
        case 51, 53, 55: return "霧雨"
        case 56, 57: return "凍雨"
        case 61, 80: return "小雨"
        case 63, 81: return "雨"
        case 65, 82: return "大雨"
        case 66, 67: return "凍る雨"
        case 71, 85: return "小雪"
        case 73: return "雪"
        case 75, 86: return "大雪"
        case 77: return "霧雪"
        case 95: return "雷雨"
        case 96, 99: return "雷雨雹"
        default: return "—"
        }
    }

    // MARK: 新闻（RSS）

    static func fetchFeed(_ urlString: String) async throws -> [String] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let p = FeedParser()
        return p.parse(data)
    }
}

/// 只挑 <item>/<entry> 里的标题
final class FeedParser: NSObject, XMLParserDelegate {
    private var titles: [String] = []
    private var inItem = false
    private var inTitle = false
    private var buffer = ""

    func parse(_ data: Data) -> [String] {
        titles = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return Array(titles.prefix(12))
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let name = e.lowercased()
        if name == "item" || name == "entry" { inItem = true }
        if name == "title" && inItem { inTitle = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inTitle, let s = String(data: CDATABlock, encoding: .utf8) { buffer += s }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        let name = e.lowercased()
        if name == "title" && inTitle {
            let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { titles.append(t) }
            inTitle = false
        }
        if name == "item" || name == "entry" { inItem = false }
    }
}

// MARK: - 取值

@MainActor
enum WidgetText {

    static func value(_ w: MaskWidget, now: Date, hub: DataHub) -> String {
        let raw = build(w, now: now, hub: hub)
        // 七段管子画不出逗号，挤在一起反而看不清
        return w.style == .seg7 ? raw.replacingOccurrences(of: ",", with: "") : raw
    }

    private static func build(_ w: MaskWidget, now: Date, hub: DataHub) -> String {
        let body: String
        switch w.kind {
        case .clock:
            body = format(now, w.format.isEmpty ? "HH:mm:ss" : w.format)
        case .date:
            body = format(now, w.format.isEmpty ? "MM/dd EEE" : w.format)
        case .text:
            body = w.source
        case .quote:
            guard let q = hub.quotes[w.source] else { return joined(w.label, "——") }
            let price = number(q.price)
            if w.showChange {
                let sign = q.changePct >= 0 ? "+" : "-"
                body = "\(price) \(sign)\(String(format: "%.2f", abs(q.changePct)))%"
            } else {
                body = price
            }
        case .weather:
            guard let x = hub.weather[w.source] else { return joined(w.label, "——") }
            body = "\(x.place) \(String(format: "%.0f", x.temp))° \(DataHub.weatherWord(x.code))"
        case .news:
            let list = hub.headlines[w.source] ?? []
            body = list.isEmpty ? "——" : list.joined(separator: "　　·　　")
        }
        return joined(w.label, body)
    }

    private static func joined(_ label: String, _ body: String) -> String {
        label.isEmpty ? body : "\(label) \(body)"
    }

    private static func number(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v >= 1000 ? 0 : (v >= 10 ? 2 : 4)
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private static let fmt = DateFormatter()

    private static func format(_ d: Date, _ pattern: String) -> String {
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = pattern
        return fmt.string(from: d)
    }
}
