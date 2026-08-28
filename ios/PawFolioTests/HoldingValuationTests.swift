import Foundation
import XCTest
@testable import PawFolio

final class HoldingValuationTests: XCTestCase {
    func testFirstSettlementIsNextDayAtFourPMBeijing() throws {
        let settlement = try XCTUnwrap(
            HoldingValuation.firstInterestSettlementMilliseconds(startDate: "2026-08-20")
        )

        XCTAssertEqual(settlement, milliseconds("2026-08-21T08:00:00Z"), accuracy: 1)
    }

    func testSimpleInterestSettlesOnlyAtFourPMAndHonorsSkippedDays() throws {
        var holding = interestHolding(rate: 36.5, mode: .simple)
        holding.interestSkips = ["2026-08-21", "2026-08-21"]

        let beforeFirstSettlement = milliseconds("2026-08-21T07:59:59Z")
        let secondSettlement = milliseconds("2026-08-22T08:00:00Z")

        XCTAssertEqual(HoldingValuation.accruedInterest(for: holding, at: beforeFirstSettlement), 0)
        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: secondSettlement),
            10,
            accuracy: 0.000_001
        )
    }

    func testCompoundInterestMatchesDailyCompounding() {
        let holding = interestHolding(rate: 36.5, mode: .compound)
        let secondSettlement = milliseconds("2026-08-22T08:00:00Z")

        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: secondSettlement),
            20.01,
            accuracy: 0.000_001
        )
    }

    func testPrincipalAdjustmentStartsAtNextSettlement() {
        var holding = interestHolding(rate: 36.5, mode: .simple, principal: 15_000)
        holding.principalAdjustments = [
            PrincipalAdjustment(
                id: "p_add",
                type: .add,
                amount: 5_000,
                date: "2026-08-21",
                createdAt: milliseconds("2026-08-21T03:00:00Z")
            )
        ]

        XCTAssertEqual(
            HoldingValuation.accruedInterest(
                for: holding,
                at: milliseconds("2026-08-22T08:00:00Z")
            ),
            25,
            accuracy: 0.000_001
        )
    }

    func testFutureInterestStartHasNoAccruedInterest() {
        var holding = interestHolding(rate: 8, mode: .compound)
        holding.interestStartDate = "2026-09-01"

        XCTAssertEqual(
            HoldingValuation.accruedInterest(
                for: holding,
                at: milliseconds("2026-08-28T12:00:00Z")
            ),
            0
        )
    }

    func testDividendConfirmsOnExDateNotPayDate() {
        let holding = Holding(
            id: "h_dividend",
            symbol: "AAPL",
            assetType: .equity,
            holdingKind: .dividend,
            quantity: 10,
            costPerShare: 100,
            dividendRecords: [
                DividendRecord(
                    id: "d_1",
                    perShare: 0.25,
                    quantity: 10,
                    amount: 2.5,
                    frequency: .quarterly,
                    exDate: "2026-08-28",
                    payDate: "2026-09-10",
                    createdAt: 1
                )
            ],
            createdAt: 1
        )

        XCTAssertEqual(
            HoldingValuation.confirmedDividendIncome(
                for: holding,
                at: milliseconds("2026-08-27T15:59:59Z")
            ),
            0
        )
        XCTAssertEqual(
            HoldingValuation.confirmedDividendIncome(
                for: holding,
                at: milliseconds("2026-08-27T16:00:00Z")
            ),
            2.5
        )
    }

    func testMarketMetricsRequireARealQuote() {
        let holding = Holding(
            id: "h_market",
            symbol: "AAPL",
            holdingKind: .market,
            quantity: 3,
            costPerShare: 100,
            createdAt: 1
        )
        let now = milliseconds("2026-08-28T00:00:00Z")

        let unavailable = HoldingValuation.metrics(for: holding, marketPrice: nil, at: now)
        let available = HoldingValuation.metrics(for: holding, marketPrice: 120, at: now)

        XCTAssertFalse(unavailable.hasValue)
        XCTAssertEqual(unavailable.cost, 300)
        XCTAssertEqual(available.value, 360)
        XCTAssertEqual(available.profit, 60)
        XCTAssertEqual(available.profitPercent, 20, accuracy: 0.000_001)
    }

    private func interestHolding(
        rate: Double,
        mode: InterestMode,
        principal: Double = 10_000
    ) -> Holding {
        Holding(
            id: "h_interest",
            symbol: "USDT",
            assetType: .stable,
            holdingKind: .interest,
            principal: principal,
            annualRate: rate,
            interestMode: mode,
            interestStartDate: "2026-08-20",
            createdAt: milliseconds("2026-08-20T00:00:00Z")
        )
    }

    private func milliseconds(_ iso8601: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970 * 1_000
    }
}

