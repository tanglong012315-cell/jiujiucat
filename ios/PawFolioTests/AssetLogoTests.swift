import XCTest
@testable import PawFolio

final class AssetLogoTests: XCTestCase {
    private let index = CryptoLogoIndex(
        ids: ["BTC": 1, "ETH": 1027],
        names: ["render": 5690]
    )

    private func urls(
        _ quoteSymbol: String,
        _ assetType: AssetType,
        name: String = "",
        index: CryptoLogoIndex? = nil
    ) -> [String] {
        AssetLogoCandidates.candidates(
            quoteSymbol: quoteSymbol,
            assetType: assetType,
            name: name,
            index: index ?? self.index
        ).map(\.absoluteString)
    }

    func testEquityTriesTheStockSourceFirst() {
        let result = urls("AAPL", .equity)
        XCTAssertEqual(result.first, "https://assets.parqet.com/logos/symbol/AAPL?format=png")
        // 旧数据里漏判类型的加密货币，靠后面的加密候选兜住。
        XCTAssertTrue(result.count > 1)
    }

    func testCryptoTriesCoinMarketCapFirst() {
        let result = urls("BTC-USD", .cryptocurrency)
        XCTAssertEqual(result.first, "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png")
        XCTAssertEqual(result[1], "https://assets.coincap.io/assets/icons/btc@2x.png")
    }

    /// 代码不在表里时跳过 CMC，直接从 CoinCap 起。
    func testUnknownCryptoSkipsCoinMarketCap() {
        let result = urls("DOGE-USD", .cryptocurrency)
        XCTAssertEqual(result.first, "https://assets.coincap.io/assets/icons/doge@2x.png")
        XCTAssertFalse(result.contains { $0.contains("coinmarketcap") })
    }

    /// 代码对不上时按名称兜底：CMC 把 RNDR 改叫 RENDER 了。
    func testFallsBackToNameLookupWhenTheTickerChanged() {
        let result = urls("RNDR-USD", .cryptocurrency, name: "Render USD")
        XCTAssertEqual(result.first, "https://s2.coinmarketcap.com/static/img/coins/64x64/5690.png")
    }

    func testCoinNameNormalizationMatchesTheWorker() {
        XCTAssertEqual(AssetLogoCandidates.normalizeCoinName("Render USD"), "render")
        XCTAssertEqual(AssetLogoCandidates.normalizeCoinName("Bitcoin"), "bitcoin")
        XCTAssertEqual(AssetLogoCandidates.normalizeCoinName("USD Coin"), "usdcoin")
    }

    /// 稳定生息持仓的类型是 STABLE，但填的是稳定币代码，也得先走加密源，
    /// 否则每次都要白打一次 Parqet 404。
    func testStableHoldingsUseCryptoSourcesFirst() {
        let result = urls("USDT", .stable)
        XCTAssertTrue(result.first?.contains("coincap") ?? false)
    }

    /// 手打的标的名不像代码时一个候选都不给——拿「活期」去拼地址只会白打 404。
    func testHandTypedStableNameProducesNoCandidates() {
        XCTAssertTrue(urls("活期", .stable).isEmpty)
        XCTAssertTrue(urls("", .stable).isEmpty)
    }

    /// 表是从网络上拿的，非正整数的 ID 不能拼进 URL。
    func testNonPositiveIdIsRejected() {
        let hostile = CryptoLogoIndex(ids: ["BTC": 0, "ETH": -5], names: [:])
        XCTAssertFalse(urls("BTC-USD", .cryptocurrency, index: hostile).contains { $0.contains("coinmarketcap") })
        XCTAssertFalse(urls("ETH-USD", .cryptocurrency, index: hostile).contains { $0.contains("coinmarketcap") })
    }

    func testTickerTooLongGetsNoCryptoCandidates() {
        let tooLong = String(repeating: "A", count: 21)
        XCTAssertTrue(urls(tooLong, .cryptocurrency).isEmpty)
    }
}
