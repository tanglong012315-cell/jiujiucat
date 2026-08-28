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
