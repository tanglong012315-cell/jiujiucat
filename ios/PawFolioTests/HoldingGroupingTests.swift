import XCTest
@testable import PawFolio

final class HoldingGroupingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000).timeIntervalSince1970 * 1_000

    private func market(
        id: String,
        symbol: String = "VOO",
        quantity: Double,
        cost: Double,
        price: Double?
    ) -> (Holding, Double?) {
        let holding = Holding(
            id: id,
            symbol: symbol,
            name: symbol,
            holdingKind: .market,
            quantity: quantity,
            costPerShare: cost,
            createdAt: 1_780_000_000_000
        )
        return (holding, price)
    }

    private func stable(
        id: String,
        symbol: String = "USDT",
        principal: Double,
        rate: Double,
        mode: InterestMode = .simple
    ) -> Holding {
        Holding(
            id: id,
            symbol: symbol,
            name: symbol,
            holdingKind: .interest,
            principal: principal,
            annualRate: rate,
            interestMode: mode,
            interestStartDate: "2026-01-01",
            createdAt: 1_780_000_000_000
        )
    }

    private func summary(_ pairs: [(Holding, Double?)]) -> MergedHoldingSummary? {
        let prices = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.id, $0.1) })
        return HoldingMerging.summary(for: pairs.map(\.0)) { holding in
            HoldingValuation.metrics(
                for: holding,
                marketPrice: prices[holding.id] ?? nil,
                at: self.now
            )
        }
    }

    // MARK: 分组

    func testGroupsKeepFirstAppearanceOrderAndNormalizeSymbols() {
        let holdings = [
            market(id: "a", symbol: "voo", quantity: 1, cost: 1, price: 1).0,
            market(id: "b", symbol: "AAPL", quantity: 1, cost: 1, price: 1).0,
            market(id: "c", symbol: " VOO ", quantity: 1, cost: 1, price: 1).0
        ]
        let groups = HoldingMerging.groups(for: holdings)
        XCTAssertEqual(groups.map(\.symbol), ["VOO", "AAPL"])
        XCTAssertEqual(groups[0].holdings.count, 2)
    }

    // MARK: 合计

    func testMarketGroupSumsValueAndQuantity() {
        let result = summary([
            market(id: "a", quantity: 2, cost: 100, price: 150),
            market(id: "b", quantity: 3, cost: 200, price: 150)
        ])
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?.totalCost, 800)          // 2*100 + 3*200
        XCTAssertEqual(result?.totalValue, 750)         // 5 * 150
        XCTAssertEqual(result?.detail, "5 份")
        XCTAssertEqual(result?.profitLabel, "盈亏")
    }

    /// 组里有一笔没有行情，合计就不给——半个合计比没有更容易误读。
    func testMissingQuoteInvalidatesTheWholeTotal() {
        let result = summary([
            market(id: "a", quantity: 2, cost: 100, price: 150),
            market(id: "b", quantity: 3, cost: 200, price: nil)
        ])
        XCTAssertNil(result?.totalValue)
        XCTAssertNil(result?.totalProfit)
        XCTAssertFalse(result?.hasValue ?? true)
    }

    func testStableGroupShowsTotalCostAndInterestLabel() {
        let result = summary([
            (stable(id: "a", principal: 1_000, rate: 5), nil),
            (stable(id: "b", principal: 2_000, rate: 5), nil)
        ])
        XCTAssertEqual(result?.profitLabel, "利息")
        XCTAssertTrue(result?.detail.hasPrefix("$3,000") ?? false)
    }

    /// 年化一致才标；不一致时挑一个当代表就是谎报。
    func testRateTagOnlyWhenEveryLotAgrees() {
        let same = summary([
            (stable(id: "a", principal: 1_000, rate: 5), nil),
            (stable(id: "b", principal: 2_000, rate: 5), nil)
        ])
        XCTAssertEqual(same?.rateTag, "5.00%")

        let mixed = summary([
            (stable(id: "a", principal: 1_000, rate: 5), nil),
            (stable(id: "b", principal: 2_000, rate: 8), nil)
        ])
        XCTAssertNil(mixed?.rateTag)
    }

    /// 计息方式同理：不一致就不给标签，展开后每笔各自标着自己的方式。
    func testInterestModeTagOnlyWhenEveryLotAgrees() {
        let compound = summary([
            (stable(id: "a", principal: 1_000, rate: 5, mode: .compound), nil),
            (stable(id: "b", principal: 2_000, rate: 5, mode: .compound), nil)
        ])
        XCTAssertEqual(compound?.interestModeTag, "复利")

        let mixed = summary([
            (stable(id: "a", principal: 1_000, rate: 5, mode: .compound), nil),
            (stable(id: "b", principal: 2_000, rate: 5, mode: .simple), nil)
        ])
        XCTAssertNil(mixed?.interestModeTag)
    }

    /// 生息和市场类混在一组时，份数没有意义，改说综合成本。
    func testMixedGroupFallsBackToCombinedCost() {
        let result = summary([
            market(id: "a", symbol: "X", quantity: 2, cost: 100, price: 150),
            (stable(id: "b", symbol: "X", principal: 1_000, rate: 5), nil)
        ])
        XCTAssertTrue(result?.detail.hasPrefix("综合成本") ?? false)
        XCTAssertNil(result?.rateTag)
        XCTAssertEqual(result?.profitLabel, "盈亏")
    }

    func testEmptyGroupHasNoSummary() {
        XCTAssertNil(summary([]))
    }

    // MARK: 利息小结

    func testInterestSummarySkipsGroupsWithoutInterestLots() {
        let group = [market(id: "a", quantity: 1, cost: 1, price: 1).0]
        XCTAssertNil(HoldingMerging.interestSummary(for: group, at: now))
    }

    func testInterestSummaryAddsUpEveryLot() {
        let group = [
            stable(id: "a", principal: 10_000, rate: 10),
            stable(id: "b", principal: 20_000, rate: 10)
        ]
        let result = HoldingMerging.interestSummary(for: group, at: now)
        XCTAssertNotNil(result)
        // 两笔本金合计三万、同样年化，总利息应当为正且等于各自之和。
        let individual = group.reduce(0.0) {
            $0 + HoldingValuation.accruedInterest(for: $1, at: now)
        }
        XCTAssertEqual(result?.total ?? 0, individual, accuracy: 0.0001)
        XCTAssertGreaterThan(result?.total ?? 0, 0)
    }
}
