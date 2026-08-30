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

    init(
        configuration: APIConfiguration = .production,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func search(query: String) async throws -> [AssetSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 40 else {
            throw MarketDataClientError.invalidQuery
        }

        let url = try endpoint(path: "api/search", queryItems: [
            URLQueryItem(name: "q", value: normalized)
        ])
        let data = try await responseData(from: url)
        return try MarketDataPayloadDecoder.searchResults(from: data)
    }

    func quote(symbol: String) async throws -> MarketQuote {
        let normalized = try normalizedSymbol(symbol)

        let url = try endpoint(path: "api/quote", queryItems: [
            URLQueryItem(name: "symbol", value: normalized)
        ])
        let data = try await responseData(from: url)
        return try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: normalized,
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory {
        let normalized = try normalizedSymbol(symbol)
        let url = try endpoint(path: "api/quote", queryItems: [
            URLQueryItem(name: "symbol", value: normalized),
            URLQueryItem(name: "range", value: "1y")
        ])
        let data = try await responseData(from: url)
        return try MarketDataPayloadDecoder.history(
            from: data,
            requestedSymbol: normalized,
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
    }

    private func normalizedSymbol(_ symbol: String) throws -> String {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(
            of: #"^[A-Z0-9^][A-Z0-9.^=-]{0,19}$"#,
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

enum MarketDataPayloadDecoder {
    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            let symbol: String
            let quoteSymbol: String
            let name: String
            let assetType: String
            let exchange: String
        }

        let results: [Result]
    }

    private struct QuoteResponse: Decodable {
        struct Chart: Decodable {
            let result: [Result]?
        }

        struct Result: Decodable {
            struct Meta: Decodable {
                let currency: String?
                let symbol: String?
                let regularMarketPrice: Double?
                let regularMarketTime: TimeInterval?
            }

            struct Indicators: Decodable {
                struct QuoteValues: Decodable {
                    let close: [Double?]?
                }

                let quote: [QuoteValues]?
            }

            let meta: Meta
            let timestamp: [TimeInterval]?
            let indicators: Indicators?
        }

        let chart: Chart
    }

    static func searchResults(from data: Data) throws -> [AssetSearchResult] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw MarketDataClientError.invalidResponse
        }

        return response.results.compactMap { result in
            guard let assetType = AssetType(rawValue: result.assetType),
                  !result.symbol.isEmpty,
                  !result.quoteSymbol.isEmpty else {
                return nil
            }
            return AssetSearchResult(
                symbol: result.symbol,
                quoteSymbol: result.quoteSymbol,
                name: result.name,
                assetType: assetType,
                exchange: result.exchange
            )
        }
    }

    static func quote(
        from data: Data,
        requestedSymbol: String,
        fetchedAtMilliseconds: TimeInterval
    ) throws -> MarketQuote {
        let result = try quoteResult(from: data)

        let timestamps = result.timestamp ?? []
        let closes = result.indicators?.quote?.first?.close ?? []
        let series = timestamps.enumerated().compactMap { index, timestamp -> MarketPricePoint? in
            guard closes.indices.contains(index),
                  let price = closes[index],
                  timestamp.isFinite,
                  price.isFinite,
                  price > 0 else {
                return nil
            }
            return MarketPricePoint(timestampMilliseconds: timestamp * 1_000, price: price)
        }
        .suffix(240)

        let regularPrice = result.meta.regularMarketPrice
        let price = regularPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? series.last?.price
        guard let price else {
            throw MarketDataClientError.invalidResponse
        }

        let dayStartSeconds = beijingDayStartSeconds(for: fetchedAtMilliseconds)
        let reference = zip(timestamps, closes).reduce(nil as Double?) { current, pair in
            let (timestamp, close) = pair
            guard timestamp <= dayStartSeconds,
                  let close,
                  close.isFinite,
                  close > 0 else {
                return current
            }
            return close
        } ?? price

        return MarketQuote(
            symbol: result.meta.symbol?.uppercased() ?? requestedSymbol,
            currency: result.meta.currency ?? "USD",
            price: price,
            changePercent: (price - reference) / reference * 100,
            series: Array(series),
            marketTimeMilliseconds: result.meta.regularMarketTime.map { $0 * 1_000 },
            fetchedAtMilliseconds: fetchedAtMilliseconds
        )
    }

    static func history(
        from data: Data,
        requestedSymbol: String,
        fetchedAtMilliseconds: TimeInterval
    ) throws -> MarketPriceHistory {
        let result = try quoteResult(from: data)
        let timestamps = result.timestamp ?? []
        let closes = result.indicators?.quote?.first?.close ?? []
        let series = timestamps.enumerated().compactMap { index, timestamp -> MarketPricePoint? in
            guard closes.indices.contains(index),
                  let price = closes[index],
                  timestamp.isFinite,
                  price.isFinite,
                  price > 0 else {
                return nil
            }
            return MarketPricePoint(timestampMilliseconds: timestamp * 1_000, price: price)
        }
        guard series.count > 1 else { throw MarketDataClientError.invalidResponse }

        return MarketPriceHistory(
            symbol: result.meta.symbol?.uppercased() ?? requestedSymbol,
            currency: result.meta.currency ?? "USD",
            series: series,
            fetchedAtMilliseconds: fetchedAtMilliseconds
        )
    }

    private static func quoteResult(from data: Data) throws -> QuoteResponse.Result {
        let response: QuoteResponse
        do {
            response = try JSONDecoder().decode(QuoteResponse.self, from: data)
        } catch {
            throw MarketDataClientError.invalidResponse
        }
        guard let result = response.chart.result?.first else {
            throw MarketDataClientError.invalidResponse
        }
        return result
    }

    private static func beijingDayStartSeconds(for timestampMilliseconds: TimeInterval) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        return calendar.startOfDay(for: date).timeIntervalSince1970
    }
}
