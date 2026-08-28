import XCTest
@testable import PawFolio

final class HoldingPositionAdjustmentTests: XCTestCase {
    func testMarketAddUsesWeightedAverageCost() throws {
        let result = try HoldingPositionAdjustment.applying(
            request(type: .add, amount: 2, price: 130),
            to: [marketHolding(quantity: 3, cost: 100)]
        )

        let holding = try XCTUnwrap(result.first)
        XCTAssertEqual(holding.quantity, 5)
        XCTAssertEqual(try XCTUnwrap(holding.costPerShare), 112, accuracy: 0.000_001)
        XCTAssertEqual(holding.positionAdjustments.last?.type, .add)
        XCTAssertEqual(holding.positionAdjustments.last?.price, 130)
        XCTAssertEqual(holding.updatedAt, now)
    }

    func testMarketReduceKeepsCostAndCreditsNewZeroAPRUSDT() throws {
        let result = try HoldingPositionAdjustment.applying(
            request(type: .reduce, amount: 2, price: 125),
            to: [marketHolding(quantity: 5, cost: 100)]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].quantity, 3)
        XCTAssertEqual(result[0].costPerShare, 100)
        XCTAssertNil(result[0].closedAt)

        let usdt = try XCTUnwrap(result.first(where: { $0.symbol == "USDT" }))
        XCTAssertEqual(usdt.holdingKind, .interest)
        XCTAssertEqual(usdt.principal, 250)
        XCTAssertEqual(usdt.annualRate, 0)
        XCTAssertEqual(usdt.interestMode, .simple)
        XCTAssertEqual(usdt.interestStartDate, "2026-08-28")
    }

    func testSaleAddsToExistingUSDTAtExactMillisecond() throws {
        let stable = Holding(
            id: "stable",
            symbol: "usdt",
            holdingKind: .interest,
            principal: 500,
            annualRate: 0,
            interestMode: .simple,
            interestStartDate: "2026-08-20",
            createdAt: 1
        )
        let result = try HoldingPositionAdjustment.applying(
            request(type: .reduce, amount: 1.5, price: 120),
            to: [marketHolding(quantity: 5, cost: 100), stable]
        )

        let usdt = try XCTUnwrap(result.first(where: { $0.id == "stable" }))
        let adjustment = try XCTUnwrap(usdt.principalAdjustments.last)
        XCTAssertEqual(usdt.principal, 680)
        XCTAssertEqual(adjustment.amount, 180)
        XCTAssertEqual(adjustment.date, "2026-08-28")
        XCTAssertEqual(adjustment.at, now)
        XCTAssertEqual(adjustment.createdAt, now)
    }

    func testFullSaleClosesSourceWithoutDeletingHistory() throws {
        let result = try HoldingPositionAdjustment.applying(
            request(type: .reduce, amount: 5, price: 90),
            to: [marketHolding(quantity: 5, cost: 100)]
        )

        XCTAssertEqual(result[0].quantity, 0)
        XCTAssertEqual(result[0].closedAt, now)
        XCTAssertNil(result[0].deletedAt)
        XCTAssertEqual(result[0].positionAdjustments.count, 1)
    }

    func testStableAdjustmentRecordsFutureEffectiveDateWithoutChangingPastInterest() throws {
        let holding = Holding(
            id: "stable",
            symbol: "USDT",
            holdingKind: .interest,
            principal: 10_000,
            annualRate: 36.5,
            interestMode: .simple,
            interestStartDate: "2026-08-20",
            createdAt: 1
        )
        let before = HoldingValuation.accruedInterest(
            for: holding,
            at: milliseconds("2026-08-28T08:00:00Z")
        )
        let result = try HoldingPositionAdjustment.applying(
            HoldingAdjustmentRequest(
                holdingID: "stable",
                type: .add,
                amount: 5_000,
                effectiveDate: "2026-08-30",
                occurredAt: now
            ),
            to: [holding]
        )

        XCTAssertEqual(result[0].principal, 15_000)
        XCTAssertEqual(result[0].principalAdjustments.last?.date, "2026-08-30")
        XCTAssertEqual(
            HoldingValuation.accruedInterest(
                for: result[0],
                at: milliseconds("2026-08-28T08:00:00Z")
            ),
            before,
            accuracy: 0.000_001
        )
    }

    func testStableReductionRejectsPastDateAndFullRedemption() {
        let holding = Holding(
            id: "stable",
            symbol: "USDT",
            holdingKind: .interest,
            principal: 1_000,
            annualRate: 0,
            interestMode: .simple,
            interestStartDate: "2026-08-20",
            createdAt: 1
        )

        XCTAssertThrowsError(
            try HoldingPositionAdjustment.applying(
                HoldingAdjustmentRequest(
                    holdingID: "stable",
                    type: .reduce,
                    amount: 100,
                    effectiveDate: "2026-08-27",
                    occurredAt: now
                ),
                to: [holding]
            )
        ) { XCTAssertEqual($0 as? HoldingAdjustmentError, .effectiveDateBeforeToday) }

        XCTAssertThrowsError(
            try HoldingPositionAdjustment.applying(
                HoldingAdjustmentRequest(
                    holdingID: "stable",
                    type: .reduce,
                    amount: 1_000,
                    effectiveDate: "2026-08-28",
                    occurredAt: now
                ),
                to: [holding]
            )
        ) { XCTAssertEqual($0 as? HoldingAdjustmentError, .insufficientPrincipal) }
    }

    func testHybridAdjustmentRecordsInterestPrincipalChange() throws {
        var holding = marketHolding(quantity: 10, cost: 100, kind: .hybrid)
        holding.annualRate = 10
        holding.interestMode = .simple
        holding.interestStartDate = "2026-08-20"

        let result = try HoldingPositionAdjustment.applying(
            request(type: .add, amount: 2, price: 150),
            to: [holding]
        )

        XCTAssertEqual(result[0].quantity, 12)
        XCTAssertEqual(
            try XCTUnwrap(result[0].costPerShare),
            108.333_333_333,
            accuracy: 0.000_001
        )
        XCTAssertEqual(result[0].principalAdjustments.last?.type, .add)
        XCTAssertEqual(
            try XCTUnwrap(result[0].principalAdjustments.last?.amount),
            300,
            accuracy: 0.000_001
        )
    }

    func testDividendAdjustmentUpdatesOnlyFutureRecords() throws {
        var holding = marketHolding(quantity: 10, cost: 100, kind: .dividend)
        holding.dividendRecords = [
            dividend(id: "confirmed", quantity: 10, exDate: "2026-08-28"),
            dividend(id: "future", quantity: 10, exDate: "2026-09-01")
        ]

        let result = try HoldingPositionAdjustment.applying(
            request(type: .reduce, amount: 4, price: 120),
            to: [holding]
        )

        XCTAssertEqual(result[0].dividendRecords[0].quantity, 10)
        XCTAssertEqual(result[0].dividendRecords[0].amount, 5)
        XCTAssertEqual(result[0].dividendRecords[1].quantity, 6)
        XCTAssertEqual(result[0].dividendRecords[1].amount, 3)
    }

    func testClosedHistoryRetentionIsExactlyFourHundredDays() {
        var recent = marketHolding(quantity: 0, cost: 100)
        recent.id = "recent"
        recent.closedAt = now - 399 * HoldingValuation.dayMilliseconds
        var expired = recent
        expired.id = "expired"
        expired.closedAt = now - HoldingPositionAdjustment.closedHistoryRetentionMilliseconds

        let result = HoldingPositionAdjustment.retainedClosedHistory(
            from: [recent, expired, marketHolding(quantity: 1, cost: 100)],
            at: now
        )

        XCTAssertEqual(Set(result.map(\.id)), ["recent", "market"])
    }

    private let now = ISO8601DateFormatter()
        .date(from: "2026-08-28T06:15:42Z")!
        .timeIntervalSince1970 * 1_000 + 123

    private func request(
        type: PositionAdjustmentKind,
        amount: Double,
        price: Double
    ) -> HoldingAdjustmentRequest {
        HoldingAdjustmentRequest(
            holdingID: "market",
            type: type,
            amount: amount,
            transactionPrice: price,
            occurredAt: now
        )
    }

    private func marketHolding(
        quantity: Double,
        cost: Double,
        kind: HoldingKind = .market
    ) -> Holding {
        Holding(
            id: "market",
            symbol: "AAPL",
            assetType: .equity,
            holdingKind: kind,
            quantity: quantity,
            costPerShare: cost,
            createdAt: 1
        )
    }

    private func dividend(id: String, quantity: Double, exDate: String) -> DividendRecord {
        DividendRecord(
            id: id,
            perShare: 0.5,
            quantity: quantity,
            amount: quantity * 0.5,
            frequency: .quarterly,
            exDate: exDate,
            payDate: "",
            createdAt: 1
        )
    }

    private func milliseconds(_ iso8601: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970 * 1_000
    }
}
