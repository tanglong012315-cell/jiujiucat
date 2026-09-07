import Foundation

/// 交易所直连地址。
///
/// ⛔ **行情不能经过自己的 Worker。** 2026-09-07 实测：Binance 对 Cloudflare
/// 出口 IP 返回 403（api.binance.com 和 www.binance.com 都拦），OKX 返回 429，
/// 而手机和浏览器直连全部 200 —— 它们拦的是数据中心 IP，不是地区。当时把报价
/// 做成 Worker 代理，上线即全线 502。
enum MarketEndpoints {
    static let binance = "https://api.binance.com"
    static let equity = "https://www.binance.com/bapi/equity/v1/public/equity"
    static let okx = "https://www.okx.com"
}

struct APIConfiguration: Equatable, Sendable {
    let baseURL: URL

    static let production = Self(
        baseURL: URL(string: "https://www.jiujiucat.win/")!
    )
}

enum MarketDataClientError: LocalizedError, Equatable {
    case invalidQuery
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            "请输入有效的标的代码或名称。"
        case .invalidResponse:
            "行情服务返回了无法识别的数据。"
        case .unavailable:
            "行情服务暂时不可用。"
        }
    }
}

protocol MarketDataServing: Sendable {
    func search(query: String) async throws -> [AssetSearchResult]
    func quote(symbol: String) async throws -> MarketQuote
    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory
}

/// 目录缓存。
///
/// 目录约 400KB，不该每次冷启动都重新解析，更不该并发拉好几份。Worker 在
/// `/api/catalog` 上带了 `Cache-Control: max-age=21600`，磁盘那一层由 URLSession
/// 的协议缓存负责；这个 actor 只管进程内的那份解析结果和「同一时刻只拉一次」。
actor MarketCatalogCache {
    static let shared = MarketCatalogCache()

    private var catalog: MarketCatalog?
    private var loadedAt: Date?
    private var inFlight: Task<MarketCatalog, Never>?
    private static let ttl: TimeInterval = 6 * 60 * 60

    /// `seeded` 让测试直接给一份目录，避免把目录请求也塞进网络桩里 ——
    /// 那样每个桩都得同时会回答「目录」和「报价」两种请求，很快就失控。
    init(seeded: MarketCatalog? = nil) {
        catalog = seeded
        loadedAt = seeded == nil ? nil : Date()
    }

    func catalog(loader: @Sendable @escaping () async throws -> MarketCatalog) async -> MarketCatalog {
        if let catalog, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.ttl, !catalog.isEmpty {
            return catalog
        }
        if let inFlight { return await inFlight.value }
        let task = Task<MarketCatalog, Never> {
            do { return try await loader() } catch { return MarketCatalog.fallback }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        // 内置兜底表不当成「已加载」缓存下来：它是降级态，下一次调用应该再试一次
        // 真目录，而不是揣着一张残表过一整天。
        if result != MarketCatalog.fallback {
            catalog = result
            loadedAt = Date()
        }
        return result
    }

    /// 测试用：清掉进程内缓存。
    func reset() {
        catalog = nil
        loadedAt = nil
        inFlight = nil
    }
}

extension MarketDataServing {
    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory {
        let quote = try await quote(symbol: symbol)
        guard quote.series.count > 1 else { throw MarketDataClientError.unavailable }
        return MarketPriceHistory(
            symbol: quote.symbol,
            currency: quote.currency,
            series: quote.series,
            fetchedAtMilliseconds: quote.fetchedAtMilliseconds
        )
    }
}

struct LiveMarketDataClient: MarketDataServing {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let catalogCache: MarketCatalogCache

    init(
        configuration: APIConfiguration = .production,
        session: URLSession = .shared,
        catalogCache: MarketCatalogCache = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.catalogCache = catalogCache
    }

    /// 搜索。
    ///
    /// 不再打 `/api/search` —— 那个端点已经随 Yahoo 一起下线。现在整份目录在本地，
    /// 搜索是纯内存过滤：零延迟、无请求、也就没有防抖和竞态可言。
    func search(query: String) async throws -> [AssetSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 40 else {
            throw MarketDataClientError.invalidQuery
        }
        let catalog = await loadCatalog()
        let results = catalog.search(normalized)
        // 目录降级成内置表时结果会很少，这时补上离线表，免得搜索看起来「坏了」。
        return results.isEmpty ? AssetSearchResult.offlineMatches(for: normalized) : results
    }

    func quote(symbol: String) async throws -> MarketQuote {
        let normalized = try normalizedSymbol(symbol)
        let instrument = try await resolve(normalized)
        let bars = try await fetchBars(for: instrument, daily: false)
        return try MarketDataPayloadDecoder.quote(
            bars: bars,
            requestedSymbol: normalized,
            conversionRate: try await conversionRate(for: instrument),
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory {
        let normalized = try normalizedSymbol(symbol)
        let instrument = try await resolve(normalized)
        let bars = try await fetchBars(for: instrument, daily: true)
        let rate = try await conversionRate(for: instrument)
        let series = bars
            .map { MarketPricePoint(timestampMilliseconds: $0.time, price: $0.close * rate) }
            .sorted { $0.timestampMilliseconds < $1.timestampMilliseconds }
        guard series.count > 1 else { throw MarketDataClientError.invalidResponse }
        return MarketPriceHistory(
            symbol: normalized,
            currency: "USD",
            series: series,
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    /// 取 K 线。三个场所三套响应格式，在这里归一成同一种 bar。
    ///
    /// 小时线同时提供最新价、北京日基准和迷你走势序列，一次请求全拿到。
    /// 美股接口最细就是 1H（1m / 30m 返回空，5m 直接报 488004）。
    private func fetchBars(
        for instrument: MarketInstrument,
        daily: Bool
    ) async throws -> [MarketDataPayloadDecoder.Bar] {
        if instrument.isEquity {
            let timeframe = daily ? "1D" : "1H"
            let limit = daily ? 365 : 200
            let encoded = instrument.symbol.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? instrument.symbol
            let url = URL(string:
                "\(MarketEndpoints.equity)/kline/chart?symbol=\(encoded)" +
                "&timeframe=\(timeframe)&limit=\(limit)&adjustmentMode=ADJUSTED"
            )
            return try MarketDataPayloadDecoder.equityBars(from: try await responseData(from: url!))
        }
        let pair = instrument.pair ?? instrument.symbol
        if instrument.venue == "okx" {
            let bar = daily ? "1D" : "1H"
            let url = URL(string:
                "\(MarketEndpoints.okx)/api/v5/market/candles?instId=\(pair)&bar=\(bar)&limit=\(daily ? 300 : 200)"
            )
            return try MarketDataPayloadDecoder.okxBars(from: try await responseData(from: url!))
        }
        // Binance 的 K 线支持时区偏移，日线直接按北京时间切 —— 北京日基准
        // 就是当日那根的开盘价，不用自己去盘中找。
        let interval = daily ? "1d" : "1h"
        let extra = daily ? "&limit=365" : "&limit=168"
        let url = URL(string: "\(MarketEndpoints.binance)/api/v3/klines?symbol=\(pair)&interval=\(interval)\(extra)")
        return try MarketDataPayloadDecoder.binanceBars(from: try await responseData(from: url!))
    }

    private func loadCatalog() async -> MarketCatalog {
        await catalogCache.catalog { [configuration, session] in
            // 静态资源，不经过 Worker。见 MarketCatalog 的说明。
            let url = configuration.baseURL.appendingPathComponent("catalog.json")
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MarketDataClientError.unavailable
            }
            return try MarketDataPayloadDecoder.catalog(from: data)
        }
    }

    private func resolve(_ symbol: String) async throws -> MarketInstrument {
        guard let instrument = await loadCatalog().resolve(symbol: symbol) else {
            // 覆盖不到就明确失败，不去猜一个盘口。调用方会保留上一次的缓存价格，
            // 或者显示「暂不可用」—— 都好过显示一个来路不明的数。
            throw MarketDataClientError.unavailable
        }
        return instrument
    }

    private func quoteEndpoint(for instrument: MarketInstrument, range: String?) throws -> URL {
        var items: [URLQueryItem] = []
        if instrument.isEquity {
            items.append(URLQueryItem(name: "eq", value: instrument.symbol))
        } else {
            items.append(URLQueryItem(name: "pair", value: instrument.pair ?? instrument.symbol))
        }
        if let range { items.append(URLQueryItem(name: "range", value: range)) }
        return try endpoint(path: "api/quote", queryItems: items)
    }

    /// USDT 计价的盘口要乘 USDT/USD 才是美元价。
    ///
    /// 涨跌幅**不**用换算后的价格算 —— 分子分母同乘一个数比值不变，换算只会把
    /// USDT 那 0.0x% 的汇率抖动当成标的自己的涨跌混进去。所以这个系数只作用在
    /// 价格和序列上，涨跌幅由 Worker 在原生计价里算好。
    private func conversionRate(for instrument: MarketInstrument) async throws -> Double {
        guard instrument.quoteCurrency == "USDT" else { return 1 }
        do {
            let url = URL(string: "\(MarketEndpoints.binance)/api/v3/klines?symbol=USDTUSD&interval=1h&limit=1")!
            let bars = try MarketDataPayloadDecoder.binanceBars(from: try await responseData(from: url))
            guard let rate = bars.last?.close, rate > 0 else { return 1 }
            return rate
        } catch {
            // 拿不到就按 1:1。误差 0.03% 量级，远小于「整个价格都不显示」的代价。
            return 1
        }
    }

    private func normalizedSymbol(_ symbol: String) throws -> String {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // 美股代号会带点号（BRK.B），加密的历史格式带 -USD 后缀，都要放行。
        guard normalized.range(
            of: #"^[A-Z0-9][A-Z0-9.^=-]{0,19}$"#,
            options: .regularExpression
        ) != nil else {
            throw MarketDataClientError.invalidQuery
        }
        return normalized
    }

    private func endpoint(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let endpoint = configuration.baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw MarketDataClientError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MarketDataClientError.invalidResponse
        }
        return url
    }

    // 移动网络下单次请求的瞬时失败很常见，而调用方是无并发上限地同时拉全部持仓
    // 的报价 —— 一次抖动就会让那个标的这一轮拿不到价。重试两次、间隔递增，
    // 抖动基本能被吃掉。
    private static let maxAttempts = 3
    private static let retryBackoffNanoseconds: [UInt64] = [300_000_000, 900_000_000]

    private func responseData(from url: URL) async throws -> Data {
        var lastError: Error = MarketDataClientError.unavailable

        for attempt in 0..<Self.maxAttempts {
            do {
                return try await singleResponseData(from: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as MarketDataClientError {
                // 4xx 与解析类错误重试多少次都是同样的结果，直接抛。
                guard case .unavailable = error else { throw error }
                lastError = error
            } catch {
                lastError = error
            }

            if attempt < Self.retryBackoffNanoseconds.count {
                // sleep 会响应取消：任务被取消时这里抛 CancellationError，
                // 不会白白占着一次退避等待。
                try await Task.sleep(nanoseconds: Self.retryBackoffNanoseconds[attempt])
            }
        }

        throw lastError
    }

    private func singleResponseData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  200..<300 ~= response.statusCode else {
                throw MarketDataClientError.unavailable
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MarketDataClientError {
            throw error
        } catch {
            throw MarketDataClientError.unavailable
        }
    }
}

/// Worker 响应的解码。
///
/// 2026-09-07 起 Worker 返回的是自己整理过的形状 `{price, change, series}`，
/// 不再透传上游。原来那套 Yahoo 的 `chart.result[0].indicators.quote[0].close`
/// 已经随 Yahoo 一起下线。
///
/// 涨跌幅由 Worker 按「北京时间今日」算好下发 —— 加密用 Binance K 线的 timeZone=8
/// 日开盘价，美股用北京 0 点（正好是 UTC 16:00 整点）那根小时线的开盘价。
/// 客户端不再自己找基准，两端也就不会算出两个数。
enum MarketDataPayloadDecoder {
    /// 三个场所归一后的 K 线。
    struct Bar: Equatable, Sendable {
        let time: TimeInterval   // 毫秒
        let open: Double
        let close: Double
    }

    private struct CatalogResponse: Decodable {
        // 美股 [名称, 类型]；加密 [交易对, 名称, 计价货币, 场所]。
        let eq: [String: [String]]
        let cx: [String: [String]]
    }

    static func catalog(from data: Data) throws -> MarketCatalog {
        let response: CatalogResponse
        do {
            response = try JSONDecoder().decode(CatalogResponse.self, from: data)
        } catch {
            throw MarketDataClientError.invalidResponse
        }

        var equities: [String: MarketCatalog.EquityEntry] = [:]
        equities.reserveCapacity(response.eq.count)
        for (code, row) in response.eq where row.count >= 2 {
            equities[code] = MarketCatalog.EquityEntry(
                name: row[0],
                assetType: row[1] == "ETF" ? .etf : .equity
            )
        }

        var cryptos: [String: MarketCatalog.CryptoEntry] = [:]
        cryptos.reserveCapacity(response.cx.count)
        for (code, row) in response.cx where row.count >= 3 {
            cryptos[code] = MarketCatalog.CryptoEntry(
                pair: row[0],
                name: row[1],
                quoteCurrency: row[2],
                venue: row.count >= 4 ? row[3] : "binance"
            )
        }

        guard !equities.isEmpty || !cryptos.isEmpty else {
            throw MarketDataClientError.invalidResponse
        }
        return MarketCatalog(equities: equities, cryptos: cryptos)
    }

    /// Binance 现货：`[[开盘时间, 开, 高, 低, 收, ...], ...]`，数值是字符串。
    static func binanceBars(from data: Data) throws -> [Bar] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw MarketDataClientError.invalidResponse
        }
        return rows.compactMap { row in
            guard row.count >= 5,
                  let time = (row[0] as? NSNumber)?.doubleValue,
                  let open = Double("\(row[1])"),
                  let close = Double("\(row[4])"),
                  time > 0, open > 0, close > 0 else { return nil }
            return Bar(time: time, open: open, close: close)
        }
    }

    /// Binance Stocks：`{data:{bars:[{t,o,h,l,c,...}]}}`，数值是字符串。
    static func equityBars(from data: Data) throws -> [Bar] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let rows = payload["bars"] as? [[String: Any]] else {
            throw MarketDataClientError.invalidResponse
        }
        return rows.compactMap { row in
            guard let time = (row["t"] as? NSNumber)?.doubleValue,
                  let open = Double("\(row["o"] ?? "")"),
                  let close = Double("\(row["c"] ?? "")"),
                  time > 0, open > 0, close > 0 else { return nil }
            return Bar(time: time, open: open, close: close)
        }
    }

    /// OKX：`{data:[[时间, 开, 高, 低, 收, ...]]}`，全是字符串，且**按时间倒序**。
    static func okxBars(from data: Data) throws -> [Bar] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[Any]] else {
            throw MarketDataClientError.invalidResponse
        }
        return rows.compactMap { row in
            guard row.count >= 5,
                  let time = Double("\(row[0])"),
                  let open = Double("\(row[1])"),
                  let close = Double("\(row[4])"),
                  time > 0, open > 0, close > 0 else { return nil }
            return Bar(time: time, open: open, close: close)
        }
        .sorted { $0.time < $1.time }
    }

    /// 由小时线合成一条报价。
    ///
    /// 北京 0 点正好是 UTC 16:00，而小时线对齐在整点上，所以边界那根的**开盘价**
    /// 就是北京 0 点的价格 —— 有那根就用它，比拿上一根的收盘价更准。
    /// 休市日（周末、节假日）0 点前没有成交，回退成最后收盘价、涨跌 0%。
    /// 对「北京时间今日」这个口径来说这是诚实的，不是缺陷。
    static func quote(
        bars: [Bar],
        requestedSymbol: String,
        conversionRate: Double,
        fetchedAtMilliseconds: TimeInterval
    ) throws -> MarketQuote {
        let sorted = bars.sorted { $0.time < $1.time }
        guard let latest = sorted.last else { throw MarketDataClientError.invalidResponse }

        let dayStart = beijingDayStartMilliseconds(for: fetchedAtMilliseconds)
        let base: Double
        if let boundary = sorted.first(where: { $0.time == dayStart }) {
            base = boundary.open
        } else if let prior = sorted.last(where: { $0.time <= dayStart }) {
            base = prior.close
        } else {
            base = latest.close
        }

        // 涨跌幅在原生计价里算：分子分母同乘一个数比值不变，换算只会把 USDT
        // 自己的抖动混成标的的涨跌。换算只作用在价格和序列上。
        let change = base > 0 ? (latest.close - base) / base * 100 : 0

        return MarketQuote(
            symbol: requestedSymbol,
            currency: "USD",
            price: latest.close * conversionRate,
            changePercent: change,
            series: Array(sorted.suffix(240).map {
                MarketPricePoint(timestampMilliseconds: $0.time, price: $0.close * conversionRate)
            }),
            marketTimeMilliseconds: latest.time,
            fetchedAtMilliseconds: fetchedAtMilliseconds
        )
    }

    private static func beijingDayStartMilliseconds(for timestampMilliseconds: TimeInterval) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        return calendar.startOfDay(for: date).timeIntervalSince1970 * 1_000
    }
}
