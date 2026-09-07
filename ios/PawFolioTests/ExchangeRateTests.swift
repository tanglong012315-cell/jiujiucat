import XCTest
@testable import PawFolio

final class ExchangeRateTests: XCTestCase {
    func testCrossRateConversionUsesUSDBaseRates() throws {
        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 7.2, .thb: 36, .myr: 4.5],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try XCTUnwrap(snapshot.converted(1_000, from: .cny, to: .thb))

        XCTAssertEqual(result, 5_000, accuracy: 0.000_001)
    }

    func testInvalidRateDoesNotProduceAConversion() {
        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 0, .thb: 36],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(snapshot.converted(100, from: .cny, to: .thb))
    }

    // 缓存是 `[CurrencyCode: Double]`，靠 `CodingKeyRepresentable` 才编成 JSON 对象。
    // 少了那层会被拍平成键值交替的数组，虽然还能解回来，但缓存文件就没法看了。
    func testSnapshotRoundTripsThroughJSONAsAnObject() throws {
        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 7.2],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"CNY\":7.2"))

        let decoded = try JSONDecoder().decode(ExchangeRateSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testCurrencyCodeNormalizesToUppercase() {
        XCTAssertEqual(CurrencyCode("jpy"), CurrencyCode("JPY"))
    }
}

final class CurrencyCatalogTests: XCTestCase {
    // 币种表是「添加货币」页的全集，重复代码会让列表出现两行一模一样的条目，
    // 而 `CurrencyCatalog.index` 又是用 `uniqueKeysWithValues` 建的，重复会直接崩。
    func testCatalogCodesAreUnique() {
        let codes = CurrencyCatalog.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    /// 字母索引直接吃 `all` 的顺序，没排好就会跳错组。
    func testCatalogIsSortedByCode() {
        let codes = CurrencyCatalog.all.map(\.code.rawValue)
        XCTAssertEqual(codes, codes.sorted())
    }

    /// 「只支持有 logo 的法币」：每一条都必须指向一个 `Flag*` 资源名。
    func testEveryEntryCarriesAFlagAsset() {
        for info in CurrencyCatalog.all {
            XCTAssertTrue(
                info.flagAssetName.hasPrefix("Flag"),
                "\(info.code.rawValue) 的国旗名不对：\(info.flagAssetName)"
            )
        }
    }

    func testDefaultSelectionIsInTheCatalog() {
        for code in CurrencyCatalog.defaultSelection {
            XCTAssertTrue(CurrencyCatalog.contains(code), code.rawValue)
        }
    }

    func testSearchMatchesCodeNameAndRegion() throws {
        let yen = try XCTUnwrap(CurrencyCatalog.info(for: "JPY"))

        XCTAssertTrue(yen.matches("jpy"))
        XCTAssertTrue(yen.matches("yen"))
        XCTAssertTrue(yen.matches("japan"))
        XCTAssertTrue(yen.matches(""))
        XCTAssertFalse(yen.matches("euro"))
    }

    func testCurrencyNamesAndSearchFollowTheSelectedChineseLocale() throws {
        let dollar = try XCTUnwrap(CurrencyCatalog.info(for: "USD"))
        let chinese = Locale(identifier: "zh-Hans")

        XCTAssertEqual(dollar.localizedName(locale: chinese), "美元")
        XCTAssertTrue(dollar.matches("美元", locale: chinese))
        XCTAssertEqual(CurrencyCode.usd.localizedDisplayName(locale: chinese), "美元")
    }

    func testStablecoinFavoritesAreSeparateFromFiatCatalog() {
        XCTAssertEqual(StablecoinCatalog.favorites.map(\.code), ["USDT", "USDC"])
        XCTAssertEqual(StablecoinCatalog.info(for: "usdt")?.name, "Tether USD")
        XCTAssertEqual(StablecoinCatalog.info(for: "USDC")?.logoAssetName, "LogoUSDC")
        for code in ["DAI", "USDS", "USDE", "USD1", "USDG", "PYUSD", "RLUSD", "USDD", "USDGO", "USDF", "BFUSD", "GHO"] {
            XCTAssertTrue(StablecoinCatalog.isKnown(code), "Expected \(code) to use the Fiat / Spot funding account")
        }
        XCTAssertTrue(StablecoinCatalog.isKnown(" usdg "))
        XCTAssertFalse(StablecoinCatalog.isKnown("BTC"))
        XCTAssertFalse(CurrencyCatalog.contains("USDT"))
        XCTAssertFalse(CurrencyCatalog.contains("USDC"))
    }
}
