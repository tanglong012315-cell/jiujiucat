import Foundation

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
        let data = try await responseData(from: try quoteEndpoint(for: instrument, range: nil))
        return try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: normalized,
            conversionRate: try await conversionRate(for: instrument),
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory {
        let normalized = try normalizedSymbol(symbol)
        let instrument = try await resolve(normalized)
        let data = try await responseData(from: try quoteEndpoint(for: instrument, range: "1y"))
        return try MarketDataPayloadDecoder.history(
            from: data,
            requestedSymbol: normalized,
            conversionRate: try await conversionRate(for: instrument),
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    private func loadCatalog() async -> MarketCatalog {
        await catalogCache.catalog { [configuration, session] in
            let url = configuration.baseURL.appendingPathComponent("api/catalog")
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
        guard let usdt = await loadCatalog().resolve(symbol: "USDT", assetType: .cryptocurrency),
              let pair = usdt.pair else { return 1 }
        do {
            let url = try endpoint(path: "api/quote", queryItems: [URLQueryItem(name: "pair", value: pair)])
            let data = try await responseData(from: url)
            let rate = try MarketDataPayloadDecoder.price(from: data)
            // 拿不到就按 1:1。误差 0.03% 量级，远小于「整个价格都不显示」的代价。
            return rate > 0 ? rate : 1
        } catch {
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
    private struct CatalogResponse: Decodable {
        // 美股 [名称, 类型]；加密 [交易对, 名称, 计价货币]。
        let eq: [String: [String]]
        let cx: [String: [String]]
    }

    private struct QuoteResponse: Decodable {
        let price: Double?
        let change: Double?
        /// [[毫秒时间戳, 价格], ...]
        let series: [[Double]]?
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
                quoteCurrency: row[2]
            )
        }

        guard !equities.isEmpty || !cryptos.isEmpty else {
            throw MarketDataClientError.invalidResponse
        }
        return MarketCatalog(equities: equities, cryptos: cryptos)
    }

    /// 只取价格 —— 给 USDT/USD 汇率那次调用用。
    static func price(from data: Data) throws -> Double {
        guard let response = try? JSONDecoder().decode(QuoteResponse.self, from: data),
              let price = response.price,
              price.isFinite,
              price > 0 else {
            throw MarketDataClientError.invalidResponse
        }
        return price
    }

    static func quote(
        from data: Data,
        requestedSymbol: String,
        conversionRate: Double,
        fetchedAtMilliseconds: TimeInterval
    ) throws -> MarketQuote {
        let response = try decodeQuote(from: data)
        guard let rawPrice = response.price, rawPrice.isFinite, rawPrice > 0 else {
            throw MarketDataClientError.invalidResponse
        }

        return MarketQuote(
            symbol: requestedSymbol,
            currency: "USD",
            price: rawPrice * conversionRate,
            // Worker 算不出基准时会给 null。那种情况下宁可显示 0%，也不要拿
            // 别的口径的数冒充「北京时间今日」。
            changePercent: response.change.flatMap { $0.isFinite ? $0 : nil } ?? 0,
            series: Array(pricePoints(from: response.series, conversionRate: conversionRate).suffix(240)),
            marketTimeMilliseconds: nil,
            fetchedAtMilliseconds: fetchedAtMilliseconds
        )
    }

    static func history(
        from data: Data,
        requestedSymbol: String,
        conversionRate: Double,
        fetchedAtMilliseconds: TimeInterval
    ) throws -> MarketPriceHistory {
        let response = try decodeQuote(from: data)
        let series = pricePoints(from: response.series, conversionRate: conversionRate)
        guard series.count > 1 else { throw MarketDataClientError.invalidResponse }

        return MarketPriceHistory(
            symbol: requestedSymbol,
            currency: "USD",
            series: series,
            fetchedAtMilliseconds: fetchedAtMilliseconds
        )
    }

    private static func decodeQuote(from data: Data) throws -> QuoteResponse {
        do {
            return try JSONDecoder().decode(QuoteResponse.self, from: data)
        } catch {
            throw MarketDataClientError.invalidResponse
        }
    }

    private static func pricePoints(
        from series: [[Double]]?,
        conversionRate: Double
    ) -> [MarketPricePoint] {
        (series ?? []).compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let timestamp = pair[0]
            let price = pair[1]
            guard timestamp.isFinite, timestamp > 0, price.isFinite, price > 0 else { return nil }
            return MarketPricePoint(
                timestampMilliseconds: timestamp,
                price: price * conversionRate
            )
        }
        .sorted { $0.timestampMilliseconds < $1.timestampMilliseconds }
    }
}
