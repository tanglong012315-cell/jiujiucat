import Foundation
import XCTest
@testable import PawFolio

final class MarketDataTests: XCTestCase {
    func testSearchPayloadDecodesSupportedAssetsAndDropsUnknownTypes() throws {
        let data = Data(#"""
        {
          "results": [
            {"symbol":"AAPL","quoteSymbol":"AAPL","name":"Apple Inc.","assetType":"EQUITY","exchange":"NASDAQ"},
            {"symbol":"BTC","quoteSymbol":"BTC-USD","name":"Bitcoin USD","assetType":"CRYPTOCURRENCY","exchange":"CCC"},
            {"symbol":"BAD","quoteSymbol":"BAD","name":"Unknown","assetType":"FUTURE","exchange":"TEST"}
          ]
        }
        """#.utf8)

        let results = try MarketDataPayloadDecoder.searchResults(from: data)

        XCTAssertEqual(results.map(\.symbol), ["AAPL", "BTC"])
        XCTAssertEqual(results.last?.assetType, .cryptocurrency)
    }

    func testQuotePayloadUsesBeijingMidnightReferenceAndBuildsSeries() throws {
        let beforeMidnight = Int(seconds("2026-08-27T15:30:00Z"))
        let afterMidnight = Int(seconds("2026-08-27T16:30:00Z"))
        let data = Data("""
        {
          "chart": {
            "result": [{
              "meta": {
                "currency": "USD",
                "symbol": "AAPL",
                "regularMarketPrice": 110,
                "regularMarketTime": \(afterMidnight)
              },
              "timestamp": [\(beforeMidnight), \(afterMidnight)],
              "indicators": {"quote": [{"close": [100, 105]}]}
            }],
            "error": null
          }
        }
        """.utf8)

        let quote = try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: "AAPL",
            fetchedAtMilliseconds: milliseconds("2026-08-28T05:00:00Z")
        )

        XCTAssertEqual(quote.price, 110)
        XCTAssertEqual(quote.changePercent, 10, accuracy: 0.000_001)
        XCTAssertEqual(quote.series.count, 2)
        XCTAssertEqual(quote.series.last?.price, 105)
    }

    func testQuotePayloadFallsBackToLatestValidClose() throws {
        let timestamp = Int(seconds("2026-08-27T16:30:00Z"))
        let data = Data("""
        {
          "chart": {
            "result": [{
              "meta": {"currency":"USD","symbol":"VOO","regularMarketPrice":null},
              "timestamp": [\(timestamp)],
              "indicators": {"quote": [{"close": [512.25]}]}
            }]
          }
        }
        """.utf8)

        let quote = try MarketDataPayloadDecoder.quote(
            from: data,
            requestedSymbol: "VOO",
            fetchedAtMilliseconds: milliseconds("2026-08-28T05:00:00Z")
        )

        XCTAssertEqual(quote.price, 512.25)
        XCTAssertEqual(quote.changePercent, 0)
    }

    func testOneYearHistoryDecoderRetainsMoreThanShortQuoteLimit() throws {
        let timestamps = (0..<260).map { 1_700_000_000 + $0 * 86_400 }
        let closes = (0..<260).map { Double($0 + 1) }
        let payload: [String: Any] = [
            "chart": [
                "result": [[
                    "meta": ["currency": "USD", "symbol": "VOO"],
                    "timestamp": timestamps,
                    "indicators": ["quote": [["close": closes]]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let history = try MarketDataPayloadDecoder.history(
            from: data,
            requestedSymbol: "VOO",
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
