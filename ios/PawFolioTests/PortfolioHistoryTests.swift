import XCTest
@testable import PawFolio

final class PortfolioHistoryTests: XCTestCase {
    func testRangesUseWebParitySampleCountsAndExactEndpoints() {
        let end: TimeInterval = 2_000_000_000_000

        for range in PortfolioHistoryRange.allCases {
            let timeline = range.timeline(endingAt: end)
            XCTAssertEqual(timeline.count, range.sampleCount)
            XCTAssertEqual(timeline.first!, end - range.spanMilliseconds, accuracy: 0.001)
            XCTAssertEqual(timeline.last!, end, accuracy: 0.001)
        }
    }

    func testHistoricalQuantityRewindsLaterAdjustments() {
        let holding = marketHolding(
            quantity: 8,
            adjustments: [
                PositionAdjustment(id: "add", type: .add, quantity: 3, price: 90, createdAt: 200),
                PositionAdjustment(id: "sell", type: .reduce, quantity: 5, price: 110, createdAt: 300)
            ]
        )

        XCTAssertEqual(PortfolioHistoryBuilder.quantity(for: holding, at: 100), 10)
        XCTAssertEqual(PortfolioHistoryBuilder.quantity(for: holding, at: 250), 13)
        XCTAssertEqual(PortfolioHistoryBuilder.quantity(for: holding, at: 300), 8)
    }

    func testHistoricalPrincipalPrefersExactTimestampAndFallsBackToBeijingDate() {
        var holding = interestHolding(principal: 175, createdAt: milliseconds("2026-08-20T00:00:00Z"))
        holding.principalAdjustments = [
            PrincipalAdjustment(
                id: "exact",
                type: .add,
                amount: 100,
                date: "2026-08-21",
                at: milliseconds("2026-08-21T08:00:00Z"),
                createdAt: milliseconds("2026-08-21T08:00:00Z")
            ),
            PrincipalAdjustment(
                id: "dated",
                type: .reduce,
                amount: 25,
                date: "2026-08-22",
                createdAt: milliseconds("2026-08-21T10:00:00Z")
            )
        ]

        XCTAssertEqual(
            PortfolioHistoryBuilder.principal(
                for: holding,
                at: milliseconds("2026-08-21T07:59:00Z")
            ),
            100
        )
        XCTAssertEqual(
            PortfolioHistoryBuilder.principal(
                for: holding,
                at: milliseconds("2026-08-21T08:01:00Z")
            ),
            200
        )
        XCTAssertEqual(
            PortfolioHistoryBuilder.principal(
                for: holding,
                at: milliseconds("2026-08-21T16:01:00Z")
            ),
            175
        )
    }

    func testPortfolioEndpointMatchesCurrentValuationAndClosedHoldingRemainsInPast() throws {
        let end = milliseconds("2026-08-28T12:00:00Z")
        let step = PortfolioHistoryRange.day.spanMilliseconds
            / Double(PortfolioHistoryRange.day.sampleCount - 1)
        let saleTime = end - step / 2
        var sold = marketHolding(
            quantity: 0,
            createdAt: end - PortfolioHistoryRange.day.spanMilliseconds,
            adjustments: [
                PositionAdjustment(id: "sell", type: .reduce, quantity: 2, price: 100, createdAt: saleTime)
            ]
        )
        sold.closedAt = saleTime
        let cash = interestHolding(principal: 200, createdAt: saleTime)
        let history = MarketPriceHistory(
            symbol: "AAPL",
            currency: "USD",
            series: [
                MarketPricePoint(timestampMilliseconds: end - PortfolioHistoryRange.day.spanMilliseconds, price: 90),
                MarketPricePoint(timestampMilliseconds: end, price: 100)
            ],
            fetchedAtMilliseconds: end
        )

        let result = try XCTUnwrap(
            PortfolioHistoryBuilder.build(
                holdings: [sold, cash],
                currentPrices: [:],
                shortHistories: ["AAPL": history],
                oneYearHistories: [:],
                range: .day,
                endingAt: end
            )
        )

        XCTAssertEqual(result.points[result.points.count - 2].value, 180, accuracy: 0.001)
        XCTAssertEqual(result.endValue!, 200, accuracy: 0.001)
    }

    func testEarlyGapIsDisclosedAndUsesEarliestPrice() throws {
        let end = milliseconds("2026-08-28T12:00:00Z")
        let start = end - PortfolioHistoryRange.week.spanMilliseconds
        let holding = marketHolding(quantity: 2, createdAt: start)
        let history = MarketPriceHistory(
            symbol: "AAPL",
            currency: "USD",
            series: [
                MarketPricePoint(timestampMilliseconds: start + 2 * HoldingValuation.dayMilliseconds, price: 80),
                MarketPricePoint(timestampMilliseconds: end, price: 100)
            ],
            fetchedAtMilliseconds: end
        )

        let result = try XCTUnwrap(
            PortfolioHistoryBuilder.build(
                holdings: [holding],
                currentPrices: ["AAPL": 110],
                shortHistories: ["AAPL": history],
                oneYearHistories: [:],
                range: .week,
                endingAt: end
            )
        )

        XCTAssertEqual(result.points.first?.value, 160)
        XCTAssertEqual(result.endValue, 220)
        XCTAssertEqual(
            result.coverageStartsAtMilliseconds!,
            start + 2 * HoldingValuation.dayMilliseconds,
            accuracy: 0.001
        )
    }

    func testMissingHistoryUsesCurrentPriceAndNamesEstimatedSymbol() throws {
        let end = milliseconds("2026-08-28T12:00:00Z")
        let holding = marketHolding(
            quantity: 1,
            createdAt: end - HoldingValuation.dayMilliseconds / 2
        )
        let result = try XCTUnwrap(
            PortfolioHistoryBuilder.build(
                holdings: [holding],
                currentPrices: ["AAPL": 120],
                shortHistories: [:],
                oneYearHistories: [:],
                range: .day,
                endingAt: end
            )
        )

        XCTAssertEqual(result.estimatedSymbols, ["AAPL"])
        XCTAssertEqual(result.endValue, 120)
    }

    func testMissingCurrentPriceMakesChartUnavailableLikeSummary() {
        let end = milliseconds("2026-08-28T12:00:00Z")
        let holding = marketHolding(
            quantity: 1,
            createdAt: end - HoldingValuation.dayMilliseconds / 2
        )

        XCTAssertNil(
            PortfolioHistoryBuilder.build(
                holdings: [holding],
                currentPrices: [:],
                shortHistories: [:],
                oneYearHistories: [:],
                range: .day,
                endingAt: end
            )
        )
    }

    private func marketHolding(
        quantity: Double,
        createdAt: TimeInterval = 0,
        adjustments: [PositionAdjustment] = []
    ) -> Holding {
        Holding(
            id: "market",
            symbol: "AAPL",
            quoteSymbol: "AAPL",
            name: "Apple",
            assetType: .equity,
            exchange: "NASDAQ",
            holdingKind: .market,
            quantity: quantity,
            costPerShare: 70,
            positionAdjustments: adjustments,
            createdAt: createdAt
        )
    }

    private func interestHolding(principal: Double, createdAt: TimeInterval) -> Holding {
        Holding(
            id: "cash",
            symbol: "USDT",
            name: "USDT",
            assetType: .stable,
            holdingKind: .interest,
            principal: principal,
            annualRate: 0,
            interestMode: .simple,
            interestStartDate: "2026-08-20",
            createdAt: createdAt
        )
    }

    private func milliseconds(_ iso8601: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970 * 1_000
    }
}
