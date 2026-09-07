import Foundation
import XCTest
@testable import PawFolio

final class MarketDataTests: XCTestCase {
    /// 客户端测试用的最小目录。真目录走 /api/catalog，那条路由由
    /// MarketCatalogTests 单独覆盖。
    static let testCatalog = MarketCatalog(
        equities: ["AAPL": .init(name: "Apple Inc.", assetType: .equity)],
        cryptos: [:]
    )

    // 2026-09-07：Worker 改为返回自己整理过的 {price, change, series}，不再透传
    // Yahoo 的 chart.result[0]。搜索端点整个下线，改由本地目录过滤（见
    // MarketCatalogTests）。这里只覆盖新的解码路径。

    func testQuotePayloadDecodesWorkerShape() throws {
        let data = Data(#"""
        {"price": 110, "change": 10, "series": [[1756308600000, 100], [1756312200000, 105]]}
        """#.utf8)

        let quote = try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: "AAPL",
            conversionRate: 1,
            fetchedAtMilliseconds: milliseconds("2026-08-28T05:00:00Z")
        )

        XCTAssertEqual(quote.price, 110)
        // 涨跌幅由 Worker 按「北京时间今日」算好下发，客户端不再自己找基准 ——
        // 两端各算一次就必然会出现两个数。
        XCTAssertEqual(quote.changePercent, 10, accuracy: 0.000_001)
        XCTAssertEqual(quote.series.count, 2)
        XCTAssertEqual(quote.series.last?.price, 105)
    }

    /// USDT 计价的盘口要乘 USDT/USD 才是美元价，但涨跌幅**不**乘 —— 分子分母
    /// 同乘一个数比值不变，乘了只会把汇率抖动混成标的自己的涨跌。
    func testConversionRateAppliesToPriceButNotChange() throws {
        let data = Data(#"{"price": 200, "change": -3, "series": [[1, 100], [2, 200]]}"#.utf8)

        let quote = try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: "BTC-USD",
            conversionRate: 0.9998,
            fetchedAtMilliseconds: 0
        )

        XCTAssertEqual(quote.price, 199.96, accuracy: 1e-9)
        XCTAssertEqual(quote.changePercent, -3, accuracy: 1e-9)
        XCTAssertEqual(quote.series.first?.price ?? 0, 99.98, accuracy: 1e-9)
    }

    func testQuotePayloadRejectsMissingPrice() {
        let data = Data(#"{"price": null, "change": 1, "series": []}"#.utf8)

        XCTAssertThrowsError(try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: "VOO",
            conversionRate: 1,
            fetchedAtMilliseconds: 0
        ))
    }

    func testOneYearHistoryDecoderRetainsMoreThanShortQuoteLimit() throws {
        // 分开写而不是一行 map：一行的字面量数组会让类型检查器爆掉
        // （"unable to type-check this expression in reasonable time"）。
        var series: [[Double]] = []
        for index in 0..<260 {
            let timestamp: Double = 1_700_000_000_000 + Double(index) * 86_400_000
            let price: Double = Double(index + 1)
            series.append([timestamp, price])
        }
        let data = try JSONSerialization.data(withJSONObject: ["price": 260, "change": 1, "series": series])

        let history = try MarketDataPayloadDecoder.history(
            from: data,
            requestedSymbol: "VOO",
            conversionRate: 1,
            fetchedAtMilliseconds: 2_000_000_000_000
        )

        XCTAssertEqual(history.series.count, 260)
        XCTAssertEqual(history.series.first?.price, 1)
        XCTAssertEqual(history.series.last?.price, 260)
    }

    func testOfflineSearchRanksExactSymbolFirst() {
        let results = AssetSearchResult.offlineMatches(for: "btc")

        XCTAssertEqual(results.first?.symbol, "BTC")
    }

    func testQuoteRepositoryFallsBackToFreshDiskCache() async throws {
        let location = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let quote = MarketQuote(
            symbol: "AAPL",
            currency: "USD",
            price: 110,
            changePercent: 1,
            series: [],
            marketTimeMilliseconds: nil,
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
        let online = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: ["AAPL": quote]),
            fileURL: location
        )
        _ = await online.refreshQuotes(for: ["AAPL"])

        let offline = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: [:]),
            fileURL: location
        )
        let result = await offline.refreshQuotes(for: ["AAPL"])

        XCTAssertEqual(result.quotes["AAPL"], quote)
        XCTAssertTrue(result.usedCachedValues)
        XCTAssertTrue(result.failedSymbols.isEmpty)
    }

    // 回归：抓取失败时，即使本地缓存已经很旧也要交还给上层。丢掉的话该标的
    // 会从列表上整个消失（调用方按返回值合并），表现为价格忽有忽无。
    func testQuoteRepositoryKeepsStaleCacheWhenFetchFails() async throws {
        let location = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let staleFetchedAt = (Date().timeIntervalSince1970 - 48 * 60 * 60) * 1_000
        let stale = MarketQuote(
            symbol: "AAPL",
            currency: "USD",
            price: 110,
            changePercent: 1,
            series: [],
            marketTimeMilliseconds: nil,
            fetchedAtMilliseconds: staleFetchedAt
        )
        let online = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: ["AAPL": stale]),
            fileURL: location
        )
        _ = await online.refreshQuotes(for: ["AAPL"])

        let offline = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: [:]),
            fileURL: location
        )
        let result = await offline.refreshQuotes(for: ["AAPL"])

        XCTAssertEqual(result.quotes["AAPL"]?.price, 110, "旧价也要保留，不能让标的消失")
        XCTAssertTrue(result.usedCachedValues, "用了缓存就要如实标记")
        XCTAssertTrue(result.failedSymbols.isEmpty, "有价可显示就不算 failed，避免提示自相矛盾")
    }

    // 回归：移动网络的瞬时失败要被重试吃掉，而不是让这一轮的报价整个作废。
    func testLiveClientRetriesTransientFailures() async throws {
        let body = Data(#"{"price": 110, "change": 0, "series": [[1756312200000, 110]]}"#.utf8)
        FlakyURLProtocol.reset(failuresBeforeSuccess: 2, successBody: body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlakyURLProtocol.self]
        let client = LiveMarketDataClient(
            session: URLSession(configuration: configuration),
            catalogCache: MarketCatalogCache(seeded: Self.testCatalog)
        )

        let quote = try await client.quote(symbol: "AAPL")

        XCTAssertEqual(quote.price, 110)
        XCTAssertEqual(FlakyURLProtocol.attemptCount(), 3, "应当在第 3 次尝试时成功")
    }

    // 回归：重试用尽仍失败时要如实抛错，不能无限重试。
    func testLiveClientGivesUpAfterMaxAttempts() async throws {
        FlakyURLProtocol.reset(failuresBeforeSuccess: .max, successBody: Data())

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlakyURLProtocol.self]
        let client = LiveMarketDataClient(
            session: URLSession(configuration: configuration),
            catalogCache: MarketCatalogCache(seeded: Self.testCatalog)
        )

        do {
            _ = try await client.quote(symbol: "AAPL")
            XCTFail("应当抛出 unavailable")
        } catch let error as MarketDataClientError {
            XCTAssertEqual(error, .unavailable)
        }
        XCTAssertEqual(FlakyURLProtocol.attemptCount(), 3, "最多尝试 3 次就要放弃")
    }

    // 回归：本地一个价都没有时，才算真的失败。
    func testQuoteRepositoryReportsFailureWhenNoCacheExists() async throws {
        let location = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let repository = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: [:]),
            fileURL: location
        )
        let result = await repository.refreshQuotes(for: ["AAPL"])

        XCTAssertTrue(result.quotes.isEmpty)
        XCTAssertEqual(result.failedSymbols, ["AAPL"])
        XCTAssertFalse(result.usedCachedValues)
    }

    /// 缓存写盘失败**不能拖垮本次刷新**（报价已经在手里了），但也不能像原来的
    /// `try?` 那样悄无声息——磁盘满或数据保护未解锁时缓存会永久写不进去，
    /// 表现是每次都要重新联网、离线一片空白，而且完全查不到原因。
    func testCacheWriteFailureIsCountedButDoesNotBreakTheRefresh() async throws {
        // 把缓存目录的位置先占成一个**文件**，`createDirectory` 就一定会失败。
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawfolio-unwritable-\(UUID().uuidString)", isDirectory: false)
        try Data("occupied".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let quote = MarketQuote(
            symbol: "AAPL",
            currency: "USD",
            price: 100,
            changePercent: 0,
            series: [],
            marketTimeMilliseconds: nil,
            fetchedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
        let repository = CachedMarketQuoteRepository(
            client: StubMarketDataClient(quotes: ["AAPL": quote]),
            fileURL: blocker.appendingPathComponent("quotes.json", isDirectory: false)
        )

        let result = await repository.refreshQuotes(for: ["AAPL"])

        XCTAssertEqual(result.quotes["AAPL"]?.price, 100)
        XCTAssertTrue(result.failedSymbols.isEmpty)
        let failures = await repository.cacheWriteFailureCount
        XCTAssertEqual(failures, 1)
    }

    func testOneYearHistoryRepositoryReusesFreshDiskCache() async throws {
        let location = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let now = Date().timeIntervalSince1970 * 1_000
        let history = MarketPriceHistory(
            symbol: "AAPL",
            currency: "USD",
            series: [
                MarketPricePoint(timestampMilliseconds: now - 1_000, price: 100),
                MarketPricePoint(timestampMilliseconds: now, price: 110)
            ],
            fetchedAtMilliseconds: now
        )
        let onlineClient = StubMarketDataClient(quotes: [:], histories: ["AAPL": history])
        let online = CachedMarketQuoteRepository(client: onlineClient, fileURL: location)
        let first = await online.refreshOneYearHistories(for: ["AAPL"])

        let offlineClient = StubMarketDataClient(quotes: [:])
        let offline = CachedMarketQuoteRepository(client: offlineClient, fileURL: location)
        let second = await offline.refreshOneYearHistories(for: ["AAPL"])

        XCTAssertEqual(first.histories["AAPL"], history)
        XCTAssertEqual(second.histories["AAPL"], history)
        XCTAssertTrue(second.usedCachedValues)
        let requestCount = await offlineClient.oneYearHistoryCallCount()
        XCTAssertEqual(requestCount, 0)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pawfolio-market-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("quotes.json", isDirectory: false)
    }

    private func seconds(_ iso8601: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970
    }

    private func milliseconds(_ iso8601: String) -> TimeInterval {
        seconds(iso8601) * 1_000
    }
}

/// 拦在 URLSession 层：重试逻辑在 LiveMarketDataClient.responseData 里，
/// stub 更上层的 MarketDataServing 根本走不到它。
final class FlakyURLProtocol: URLProtocol {
    /// 前 `failuresBeforeSuccess` 次返回 503，之后返回真实报文。
    nonisolated(unsafe) static var failuresBeforeSuccess = 0
    nonisolated(unsafe) static var successBody = Data()
    nonisolated(unsafe) static private(set) var attempts = 0
    private static let lock = NSLock()

    static func reset(failuresBeforeSuccess: Int, successBody: Data) {
        lock.lock(); defer { lock.unlock() }
        Self.failuresBeforeSuccess = failuresBeforeSuccess
        Self.successBody = successBody
        attempts = 0
    }

    static func attemptCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return attempts
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.attempts += 1
        let shouldFail = Self.attempts <= Self.failuresBeforeSuccess
        let body = Self.successBody
        Self.lock.unlock()

        let status = shouldFail ? 503 : 200
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !shouldFail {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

private actor StubMarketDataClient: MarketDataServing {
    let quotes: [String: MarketQuote]
    let histories: [String: MarketPriceHistory]
    private var historyCallCount = 0

    init(
        quotes: [String: MarketQuote],
        histories: [String: MarketPriceHistory] = [:]
    ) {
        self.quotes = quotes
        self.histories = histories
    }

    func search(query: String) async throws -> [AssetSearchResult] {
        []
    }

    func quote(symbol: String) async throws -> MarketQuote {
        guard let quote = quotes[symbol] else {
            throw MarketDataClientError.unavailable
        }
        return quote
    }

    func oneYearHistory(symbol: String) async throws -> MarketPriceHistory {
        historyCallCount += 1
        guard let history = histories[symbol] else {
            throw MarketDataClientError.unavailable
        }
        return history
    }

    func oneYearHistoryCallCount() -> Int {
        historyCallCount
    }
}
