import XCTest
@testable import PawFolio

final class PreferencesStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: UserDefaultsPreferencesStore!

    override func setUp() {
        super.setUp()
        suiteName = "pawfolio.tests.preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = UserDefaultsPreferencesStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testSelectionRoundTrips() {
        XCTAssertNil(store.loadSelection())

        store.save(selection: [.thb, .cny, "JPY"])

        XCTAssertEqual(store.loadSelection(), [.thb, .cny, "JPY"])
    }

    func testSnapshotRoundTrips() {
        XCTAssertNil(store.loadSnapshot())

        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 7.2],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.save(snapshot: snapshot)

        XCTAssertEqual(store.loadSnapshot(), snapshot)
    }

    func testHistoryRangeRoundTrips() {
        XCTAssertNil(store.loadHistoryRange())

        store.save(historyRange: .month)

        XCTAssertEqual(store.loadHistoryRange(), .month)
    }

    func testSpotAssetOrderRoundTrips() {
        let order = [
            LedgerAsset(code: "USDT", kind: .stablecoin),
            LedgerAsset(code: "CNY", kind: .fiat),
            LedgerAsset(code: "USDG", kind: .stablecoin),
        ]

        XCTAssertEqual(store.loadSpotAssetOrder(), [])
        store.save(spotAssetOrder: order)
        XCTAssertEqual(store.loadSpotAssetOrder(), order)
    }

    func testSpotAssetOrderDropsDuplicateEntries() {
        let cny = LedgerAsset(code: "CNY", kind: .fiat)
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)

        store.save(spotAssetOrder: [cny, usdt, cny])

        XCTAssertEqual(store.loadSpotAssetOrder(), [cny, usdt])
    }

    func testTradingAssetOrderRoundTripsAndDropsDuplicateEntries() {
        let btc = LedgerAsset(code: "BTC", kind: .cryptocurrency)
        let eth = LedgerAsset(code: "ETH", kind: .cryptocurrency)

        XCTAssertEqual(store.loadTradingAssetOrder(), [])
        store.save(tradingAssetOrder: [eth, btc, eth])

        XCTAssertEqual(store.loadTradingAssetOrder(), [eth, btc])
    }

    func testEarnProductOrderRoundTripsAndDropsInvalidEntries() {
        XCTAssertEqual(store.loadEarnProductOrder(), [])
        store.save(earnProductOrder: ["usdt-flexible", "", "btc-fixed", "usdt-flexible"])

        XCTAssertEqual(store.loadEarnProductOrder(), ["usdt-flexible", "btc-fixed"])
    }

    /// V1.2.0 把漏了 `pawfolio.` 前缀的旧 key 改了名。老用户已经选好的区间必须搬
    /// 过去，不能静默丢掉——这正是这次改名唯一动到持久化的地方。
    func testLegacyHistoryRangeKeyIsMigratedOnce() {
        defaults.set(PortfolioHistoryRange.year.rawValue, forKey: "portfolio.historyRange")

        XCTAssertEqual(store.loadHistoryRange(), .year)
        // 搬完就把旧 key 清掉，下次直接读新 key。
        XCTAssertNil(defaults.string(forKey: "portfolio.historyRange"))
        XCTAssertEqual(store.loadHistoryRange(), .year)
    }

    /// 新 key 已经有值时不去看旧 key：否则用户改过区间之后，残留的旧值会把它顶回去。
    func testNewKeyWinsOverALeftoverLegacyValue() {
        defaults.set(PortfolioHistoryRange.year.rawValue, forKey: "portfolio.historyRange")
        store.save(historyRange: .day)

        XCTAssertEqual(store.loadHistoryRange(), .day)
    }

    func testGarbageValuesReadBackAsNil() {
        defaults.set("not-a-range", forKey: "portfolio.historyRange")
        XCTAssertNil(store.loadHistoryRange())

        defaults.set(Data("not json".utf8), forKey: "pawfolio.exchange-rate.snapshot.v2")
        XCTAssertNil(store.loadSnapshot())

        defaults.set(Data("not json".utf8), forKey: "pawfolio.portfolio.spot-asset-order.v1")
        XCTAssertEqual(store.loadSpotAssetOrder(), [])

        defaults.set(Data("not json".utf8), forKey: "pawfolio.portfolio.trading-asset-order.v1")
        XCTAssertEqual(store.loadTradingAssetOrder(), [])
    }
}
