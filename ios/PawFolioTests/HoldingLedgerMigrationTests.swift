import XCTest
@testable import PawFolio

final class HoldingLedgerMigrationTests: XCTestCase {
    func testMigrationCreatesOpeningSnapshotWithoutChangingHoldingSchema() throws {
        let openingDate = Date(timeIntervalSince1970: 1_000)
        let stock = Holding(
            id: "stock",
            symbol: "AAPL",
            assetType: .equity,
            holdingKind: .market,
            quantity: 3,
            costPerShare: 100,
            createdAt: 1
        )
        let usdt = Holding(
            id: "earn",
            symbol: "USDT",
            assetType: .stable,
            holdingKind: .interest,
            principal: 500,
            annualRate: 4.5,
            interestMode: .simple,
            createdAt: 2
        )

        let result = HoldingLedgerMigration.migrate([stock, usdt], openingAt: openingDate)
        let projection = try LedgerProjection(entries: result.entries)

        XCTAssertEqual(Holding.currentSchemaVersion, 2)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.earnProducts.count, 1)
        XCTAssertEqual(projection.balance(
            in: .trading,
            asset: LedgerAsset(code: "AAPL", kind: .equity)
        ), 3, accuracy: 1e-9)
        XCTAssertEqual(
            projection.tradingPositions[LedgerAsset(code: "AAPL", kind: .equity)]?.costBasis ?? 0,
            300,
            accuracy: 1e-9
        )
        XCTAssertEqual(projection.balance(
            in: .earn(productID: "legacy-earn-earn"),
            asset: LedgerAsset(code: "USDT", kind: .stablecoin)
        ), 500, accuracy: 1e-9)
    }

    func testMigrationSkipsClosedAndZeroQuantityHoldings() {
        let closed = Holding(
            id: "closed",
            symbol: "BTC",
            assetType: .cryptocurrency,
            holdingKind: .market,
            quantity: 1,
            createdAt: 1,
            closedAt: 2
        )
        let zero = Holding(
            id: "zero",
            symbol: "USD",
            holdingKind: .interest,
            principal: 0,
            createdAt: 1
        )

        let result = HoldingLedgerMigration.migrate([closed, zero], openingAt: Date())

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.skippedHoldingIDs.isEmpty)
    }
}
