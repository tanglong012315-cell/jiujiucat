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
            "BTC": .init(pair: "BTCUSDT", name: "Bitcoin", quoteCurrency: "USDT"),
            "USDT": .init(pair: "USDTUSD", name: "TetherUS", quoteCurrency: "USD"),
            "STX": .init(pair: "STXUSDT", name: "Stacks", quoteCurrency: "USDT")
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
    func testDecodesCatalog() throws {
        let json = """
        {"eq":{"VOO":["Vanguard S&P 500 ETF","ETF"]},"cx":{"BTC":["BTCUSDT","Bitcoin","USDT"]}}
        """.data(using: .utf8)!
        let catalog = try MarketDataPayloadDecoder.catalog(from: json)
        XCTAssertEqual(catalog.equities["VOO"]?.assetType, .etf)
        XCTAssertEqual(catalog.cryptos["BTC"]?.pair, "BTCUSDT")
    }

    func testDecodesQuoteAndAppliesConversionRate() throws {
        let json = """
        {"price":100,"change":-1.5,"series":[[1000,90],[2000,100]]}
        """.data(using: .utf8)!
        let quote = try MarketDataPayloadDecoder.quote(
            from: json,
            requestedSymbol: "BTC-USD",
            conversionRate: 0.9998,
            fetchedAtMilliseconds: 5_000
        )
        XCTAssertEqual(quote.price, 99.98, accuracy: 1e-9)
        // 涨跌幅由 Worker 在原生计价里算好，换算系数不能作用在它上面。
        XCTAssertEqual(quote.changePercent, -1.5, accuracy: 1e-9)
        XCTAssertEqual(quote.series.last?.price ?? 0, 99.98, accuracy: 1e-9)
    }

    /// Worker 算不出北京日基准时会给 null，这时涨跌显示 0，而不是抛错让整条
    /// 报价作废 —— 价格本身仍然是有效信息。
    func testMissingChangeFallsBackToZero() throws {
        let json = #"{"price":10,"change":null,"series":[]}"#.data(using: .utf8)!
        let quote = try MarketDataPayloadDecoder.quote(
            from: json, requestedSymbol: "AAPL", conversionRate: 1, fetchedAtMilliseconds: 0
        )
        XCTAssertEqual(quote.changePercent, 0)
    }

    func testRejectsNonPositivePrice() {
        let json = #"{"price":0,"change":1,"series":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try MarketDataPayloadDecoder.quote(
            from: json, requestedSymbol: "AAPL", conversionRate: 1, fetchedAtMilliseconds: 0
        ))
    }
}
