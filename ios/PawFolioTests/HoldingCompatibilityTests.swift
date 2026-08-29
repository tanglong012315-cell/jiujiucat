import XCTest
@testable import PawFolio

final class HoldingCompatibilityTests: XCTestCase {
    func testDecodesLegacyWebDividendHoldingWithoutSchemaVersion() throws {
        let json = #"""
        {
          "id": "h_1780000000000_demo",
          "symbol": "AAPL",
          "quoteSymbol": "AAPL",
          "name": "Apple Inc.",
          "assetType": "EQUITY",
          "exchange": "NASDAQ",
          "holdingKind": "dividend",
          "quantity": 12.5,
          "costPerShare": 180,
          "priceOverride": null,
          "principal": null,
          "annualRate": null,
          "interestMode": null,
          "interestStartDate": null,
          "dividendPerShare": 0.25,
          "dividendFrequency": "quarterly",
          "dividendExDate": "2026-08-20",
          "dividendPayDate": "2026-08-28",
          "positionAdjustments": [],
          "principalAdjustments": [],
          "dividendRecords": [
            {
              "id": "d_demo",
              "perShare": 0.25,
              "quantity": 12.5,
              "amount": 3.125,
              "frequency": "quarterly",
              "exDate": "2026-08-20",
              "payDate": "2026-08-28",
              "createdAt": 1780000000000
            }
          ],
          "dividendRecordId": "d_demo",
          "createdAt": 1780000000000
        }
        """#

        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))

        XCTAssertEqual(holding.schemaVersion, 1)
        XCTAssertEqual(holding.holdingKind, .dividend)
        XCTAssertEqual(holding.assetType, .equity)
        XCTAssertEqual(holding.quantity, 12.5)
        XCTAssertEqual(holding.dividendRecords.first?.amount, 3.125)
        XCTAssertEqual(holding.interestSkips, [])
        XCTAssertEqual(holding.currentCostBasis, 2_250)
        XCTAssertFalse(holding.isDeleted)
    }

    func testDecodesLegacyStableHoldingWithMissingArraysAndInterestMode() throws {
        let json = #"""
        {
          "id": "h_stable",
          "symbol": "USDT",
          "quoteSymbol": "USDT",
          "name": "USDT",
          "assetType": null,
          "holdingKind": "interest",
          "principal": 5000,
          "annualRate": 4.5,
          "interestStartDate": "2026-08-20",
          "createdAt": 1780000000000
        }
        """#

        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))

        XCTAssertEqual(holding.holdingKind, .interest)
        XCTAssertEqual(holding.interestMode, .simple)
        XCTAssertEqual(holding.currentCostBasis, 5_000)
        XCTAssertTrue(holding.positionAdjustments.isEmpty)
        XCTAssertTrue(holding.principalAdjustments.isEmpty)
    }

    func testNewHoldingEncodesCurrentSchemaVersion() throws {
        let holding = Holding(
            id: "h_native",
            symbol: "BTC",
            quoteSymbol: "BTC-USD",
            name: "Bitcoin USD",
            assetType: .cryptocurrency,
            exchange: "CCC",
            holdingKind: .market,
            quantity: 0.1,
            costPerShare: 60_000,
            createdAt: 1_780_000_000_000
        )

        let data = try JSONEncoder().encode(holding)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? Int, Holding.currentSchemaVersion)
        XCTAssertEqual(object["holdingKind"] as? String, "market")
        XCTAssertEqual(object["assetType"] as? String, "CRYPTOCURRENCY")
    }

    func testDeletionTombstoneRoundTrips() throws {
        let holding = Holding(
            id: "h_deleted",
            symbol: "VOO",
            holdingKind: .market,
            quantity: 2,
            costPerShare: 500,
            createdAt: 1_780_000_000_000,
            updatedAt: 1_780_000_100_000,
            deletedAt: 1_780_000_100_000
        )

        let data = try JSONEncoder().encode(holding)
        let decoded = try JSONDecoder().decode(Holding.self, from: data)

        XCTAssertTrue(decoded.isDeleted)
        XCTAssertEqual(decoded.deletedAt, 1_780_000_100_000)
    }

    func testNoteIsTrimmedToTwentyCharactersAndSurvivesEncoding() throws {
        let holding = Holding(
            id: "h_note",
            symbol: "VOO",
            holdingKind: .market,
            quantity: 1,
            costPerShare: 500,
            note: "  这是一条二十一个字的备注刚好多出来一个字啊  ",
            createdAt: 1_780_000_000_000
        )

        // 首尾空白去掉后是 21 个字，第 21 个「啊」必须被裁掉。
        XCTAssertEqual(holding.note?.count, 20)
        XCTAssertEqual(holding.note, "这是一条二十一个字的备注刚好多出来一个字")

        let decoded = try JSONDecoder().decode(Holding.self, from: JSONEncoder().encode(holding))
        XCTAssertEqual(decoded.note, holding.note)
    }

    func testBlankNoteBecomesNilSoItNeverRendersAnEmptyRow() throws {
        for raw in ["", "   ", "\n\t"] {
            let holding = Holding(
                id: "h_blank",
                symbol: "VOO",
                holdingKind: .market,
                note: raw,
                createdAt: 1_780_000_000_000
            )
            XCTAssertNil(holding.note, "「\(raw)」应当被当作没有备注")
        }
    }

    func testEmojiNoteCountsByCharacterNotUTF16() throws {
        // 每个 emoji 在 UTF-16 里占两个单元。按 utf16.count 裁会只留下 10 个，
        // 而且可能把代理对从中间劈开。
        let holding = Holding(
            id: "h_emoji",
            symbol: "BTC",
            holdingKind: .market,
            note: String(repeating: "🐱", count: 25),
            createdAt: 1_780_000_000_000
        )

        XCTAssertEqual(holding.note?.count, 20)
        XCTAssertEqual(holding.note, String(repeating: "🐱", count: 20))
    }

    func testLegacyHoldingWithoutNoteDecodesToNil() throws {
        let json = #"""
        {
          "id": "h_legacy",
          "symbol": "AAPL",
          "holdingKind": "market",
          "createdAt": 1780000000000
        }
        """#

        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))
        XCTAssertNil(holding.note)
    }

    func testOverlongNoteFromCloudIsTrimmedOnDecode() throws {
        // Web 的 maxlength 只是个表单限制，绕过它写进云端的长备注两端都得收得住。
        let json = #"""
        {
          "id": "h_cloud",
          "symbol": "AAPL",
          "holdingKind": "market",
          "note": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "createdAt": 1780000000000
        }
        """#

        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))
        XCTAssertEqual(holding.note, String(repeating: "a", count: 20))
    }

    func testUnknownLegacyKindsFailSoftInsteadOfDroppingRecord() throws {
        let json = #"""
        {
          "id": "h_unknown",
          "symbol": "TEST",
          "assetType": "FUTURE_TYPE",
          "holdingKind": "future_kind",
          "createdAt": 1780000000000
        }
        """#

        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))

        XCTAssertEqual(holding.holdingKind, .market)
        XCTAssertNil(holding.assetType)
    }
}
