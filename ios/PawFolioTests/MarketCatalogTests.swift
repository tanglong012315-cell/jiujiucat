import XCTest
@testable import PawFolio

final class MarketCatalogTests: XCTestCase {
    private let catalog = MarketCatalog(
        equities: [
            "VOO": .init(name: "Vanguard S&P 500 ETF", assetType: .etf),
            "AAPL": .init(name: "Apple Inc. Common Stock", assetType: .equity),
            "STX": .init(name: "Seagate", assetType: .equity)
        ],
        cryptos: [
            "BTC": .init(pair: "BTCUSDT", name: "Bitcoin", quoteCurrency: "USDT", venue: "binance"),
            "USDT": .init(pair: "USDTUSD", name: "TetherUS", quoteCurrency: "USD", venue: "binance"),
            "STX": .init(pair: "STXUSDT", name: "Stacks", quoteCurrency: "USDT", venue: "binance")
        ]
    )

    func testResolvesEquityBySymbol() {
        let voo = catalog.resolve(symbol: "VOO")
        XCTAssertEqual(voo?.isEquity, true)
        XCTAssertNil(voo?.pair)
        XCTAssertEqual(voo?.quoteCurrency, "USD")
        XCTAssertEqual(voo?.assetType, .etf)
    }

    /// 旧持仓里加密标的存的是 Yahoo 格式的 BTC-USD，必须仍然解析得出来，
    /// 否则升级后所有加密持仓一起失去价格。
    func testResolvesLegacyYahooCryptoSymbol() {
        let btc = catalog.resolve(symbol: "BTC-USD")
        XCTAssertEqual(btc?.isEquity, false)
        XCTAssertEqual(btc?.pair, "BTCUSDT")
        XCTAssertEqual(btc?.quoteCurrency, "USDT")
    }

    /// 少数代号在美股和加密两边都存在（STX = Seagate / Stacks）。
    /// 给了 assetType 就必须按类型解析，不能靠运气。
    func testAssetTypeDisambiguatesCollidingSymbol() {
        XCTAssertEqual(catalog.resolve(symbol: "STX", assetType: .equity)?.pair, nil)
        XCTAssertEqual(catalog.resolve(symbol: "STX", assetType: .cryptocurrency)?.pair, "STXUSDT")
    }

    /// STABLE 是手填生息持仓的类型，标的名就是 USDT 这类币，要走加密那张表。
    func testStableAssetTypeResolvesToCryptoPair() {
        let usdt = catalog.resolve(symbol: "USDT", assetType: .stable)
        XCTAssertEqual(usdt?.pair, "USDTUSD")
        XCTAssertEqual(usdt?.quoteCurrency, "USD")
    }

    func testUnknownSymbolResolvesToNil() {
        XCTAssertNil(catalog.resolve(symbol: "NOTLISTED"))
    }

    func testSearchRanksExactCodeFirst() {
        let results = catalog.search("STX")
        XCTAssertEqual(results.first?.symbol, "STX")
    }

    func testSearchMatchesCompanyName() {
        let results = catalog.search("Vanguard")
        XCTAssertEqual(results.first?.symbol, "VOO")
    }

    /// 搜索结果里的加密标的要带 -USD 后缀，和历史持仓的存储格式保持一致，
    /// 否则同一个 BTC 会在列表里出现两条。
    func testSearchKeepsLegacyCryptoQuoteSymbol() {
        let btc = catalog.search("BTC").first
        XCTAssertEqual(btc?.symbol, "BTC")
        XCTAssertEqual(btc?.quoteSymbol, "BTC-USD")
    }

    func testSearchIgnoresBlankQuery() {
        XCTAssertTrue(catalog.search("   ").isEmpty)
    }

    /// 内置兜底表必须覆盖行情条那几个标的和两个主要稳定币 —— 目录端点挂掉时
    /// 它是唯一还能出价的东西。
    func testFallbackCatalogCoversTickerAndStablecoins() {
        for symbol in ["BTC", "USDT", "USDC"] {
            XCTAssertNotNil(MarketCatalog.fallback.resolve(symbol: symbol, assetType: .cryptocurrency), symbol)
        }
        for symbol in ["MSTR", "QQQ"] {
            XCTAssertNotNil(MarketCatalog.fallback.resolve(symbol: symbol, assetType: .equity), symbol)
        }
    }
}

final class MarketDataPayloadDecoderTests: XCTestCase {
    func testDecodesCatalogIncludingVenue() throws {
        let json = """
        {"eq":{"VOO":["Vanguard S&P 500 ETF","ETF"]},
         "cx":{"BTC":["BTCUSDT","Bitcoin","USDT","binance"],
               "OKB":["","OKB","USD","cmc"]}}
        """.data(using: .utf8)!
        let catalog = try MarketDataPayloadDecoder.catalog(from: json)
        XCTAssertEqual(catalog.equities["VOO"]?.assetType, .etf)
        XCTAssertEqual(catalog.cryptos["BTC"]?.venue, "binance")
        // Binance 不上架竞争对手的平台币，OKB 只能走 CMC。
        XCTAssertEqual(catalog.cryptos["OKB"]?.venue, "cmc")
    }

    /// 旧目录没有第 4 个字段，要默认成 binance，不能整条丢掉。
    func testCatalogDefaultsVenueWhenMissing() throws {
        let json = #"{"eq":{},"cx":{"ETH":["ETHUSDT","Ethereum","USDT"]}}"#.data(using: .utf8)!
        let catalog = try MarketDataPayloadDecoder.catalog(from: json)
        XCTAssertEqual(catalog.cryptos["ETH"]?.venue, "binance")
    }

    func testBinanceBarsDecodeStringNumbers() throws {
        let json = #"[[1788710400000,"1.5","2","1","1.8",0],[1788714000000,"1.8","2","1","1.9",0]]"#
            .data(using: .utf8)!
        let bars = try MarketDataPayloadDecoder.binanceBars(from: json)
        XCTAssertEqual(bars.count, 2)
        XCTAssertEqual(bars.last?.close, 1.9)
    }

    func testCMCQuoteDecodes() throws {
        let json = #"{"quotes":{"OKB":{"price":114.55,"change24h":0.49}}}"#.data(using: .utf8)!
        let result = try MarketDataPayloadDecoder.cmcQuote(from: json, symbol: "OKB")
        XCTAssertEqual(result.price, 114.55)
        XCTAssertEqual(result.change, 0.49)
    }

    func testCMCQuoteRejectsMissingSymbol() {
        let json = #"{"quotes":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try MarketDataPayloadDecoder.cmcQuote(from: json, symbol: "OKB"))
    }

    func testEquityBarsDecodeNestedShape() throws {
        let json = #"{"data":{"bars":[{"t":1788710400000,"o":"700","h":"1","l":"1","c":"707.66"}]}}"#
            .data(using: .utf8)!
        let bars = try MarketDataPayloadDecoder.equityBars(from: json)
        XCTAssertEqual(bars.first?.open, 700)
        XCTAssertEqual(bars.first?.close, 707.66)
    }

    /// 北京 0 点是 UTC 16:00，正好落在整点小时线的边界上，所以基准取那根的
    /// **开盘价**最准。
    func testQuoteUsesBeijingMidnightBarOpenAsBasis() throws {
        let dayStart: TimeInterval = 1_788_710_400_000   // 2026-09-07 00:00 北京
        let bars = [
            MarketDataPayloadDecoder.Bar(time: dayStart - 3_600_000, open: 90, close: 95),
            MarketDataPayloadDecoder.Bar(time: dayStart, open: 100, close: 105),
            MarketDataPayloadDecoder.Bar(time: dayStart + 3_600_000, open: 105, close: 110)
        ]
        let quote = try MarketDataPayloadDecoder.quote(
            bars: bars, requestedSymbol: "VOO", conversionRate: 1,
            fetchedAtMilliseconds: dayStart + 7_200_000
        )
        XCTAssertEqual(quote.price, 110)
        // 基准是边界那根的开盘价 100，不是上一根的收盘价 95。
        XCTAssertEqual(quote.changePercent, 10, accuracy: 1e-9)
    }

    /// 休市日 0 点前没有成交，基准回退成最后收盘价 —— 涨跌 0%。
    /// 对「北京今日」这个口径来说这是诚实的。
    func testQuoteFallsBackToLastCloseWhenMarketWasClosed() throws {
        let dayStart: TimeInterval = 1_788_710_400_000
        let bars = [MarketDataPayloadDecoder.Bar(time: dayStart - 86_400_000, open: 700, close: 707.66)]
        let quote = try MarketDataPayloadDecoder.quote(
            bars: bars, requestedSymbol: "VOO", conversionRate: 1,
            fetchedAtMilliseconds: dayStart + 3_600_000
        )
        XCTAssertEqual(quote.price, 707.66)
        XCTAssertEqual(quote.changePercent, 0, accuracy: 1e-9)
    }

    /// 换算只作用在价格和序列上，**不能**作用在涨跌幅：分子分母同乘一个数
    /// 比值不变，乘了只会把 USDT 自己的抖动混成标的的涨跌。
    func testConversionRateAppliesToPriceButNotChange() throws {
        let dayStart: TimeInterval = 1_788_710_400_000
        let bars = [
            MarketDataPayloadDecoder.Bar(time: dayStart, open: 100, close: 100),
            MarketDataPayloadDecoder.Bar(time: dayStart + 3_600_000, open: 100, close: 200)
        ]
        let quote = try MarketDataPayloadDecoder.quote(
            bars: bars, requestedSymbol: "BTC-USD", conversionRate: 0.9998,
            fetchedAtMilliseconds: dayStart + 7_200_000
        )
        XCTAssertEqual(quote.price, 199.96, accuracy: 1e-9)
        XCTAssertEqual(quote.changePercent, 100, accuracy: 1e-9)
    }

    func testQuoteRejectsEmptyBars() {
        XCTAssertThrowsError(try MarketDataPayloadDecoder.quote(
            bars: [], requestedSymbol: "VOO", conversionRate: 1, fetchedAtMilliseconds: 0
        ))
    }
}
