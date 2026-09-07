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

    // 本金调整立即生效：生效日当天那次结算就按新本金算。
    // 36.5% 年化 = 每天 0.1%。8/20 起息、8/21 首次结算，8/21 上午（北京 11:00，
    // 当天 16:00 的结算还没发）加仓到 15000 → 8/21、8/22 各 15，共 30。
    func testPrincipalAdjustmentTakesEffectOnItsEffectiveDate() {
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
            30,
            accuracy: 0.000_001
        )
    }

    // 历史生效日是用户明确要求的重算入口。即使记录发生在当天 16:00 以后，
    // 只要选择 8/21 生效，8/21 与 8/22 两次结算都按 15000 计算。
    func testHistoricalPrincipalAdjustmentRecalculatesFromItsEffectiveDate() {
        var holding = interestHolding(rate: 36.5, mode: .simple, principal: 15_000)
        holding.principalAdjustments = [
            PrincipalAdjustment(
                id: "p_add",
                type: .add,
                amount: 5_000,
                date: "2026-08-21",
                createdAt: milliseconds("2026-08-21T09:00:00Z")
            )
        ]

        XCTAssertEqual(
            HoldingValuation.accruedInterest(
                for: holding,
                at: milliseconds("2026-08-22T08:00:00Z")
            ),
            30,
            accuracy: 0.000_001
        )
    }

    // 核心诉求：改利率不能改写已结算的历史利息。
    // 36.5% 年化 = 每天 0.1%，本金 10000 → 每天 10 元。
    // 8/20 起息、8/21 首次结算，所以到 8/23 16:00 已结 3 天（21/22/23）。
    // 利率变更生效日设在 8/23，那天起按新利率：21、22 各 10 元，23 起 5 元。
    func testRateChangeOnlyAffectsDaysFromItsEffectiveDate() {
        var holding = interestHolding(rate: 36.5, mode: .simple)
        holding.rateAdjustments = [
            RateAdjustment(
                id: "r1",
                annualRate: 18.25,
                date: "2026-08-23",
                createdAt: milliseconds("2026-08-23T00:00:00Z")
            )
        ]

        // 到 8/23：旧利率两天 20 + 新利率一天 5 = 25。
        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: milliseconds("2026-08-23T08:00:00Z")),
            25,
            accuracy: 0.000_001
        )
        // 到 8/24：再加新利率一天 5 = 30。
        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: milliseconds("2026-08-24T08:00:00Z")),
            30,
            accuracy: 0.000_001
        )
    }

    // 没有 rateAdjustments 的旧数据，行为必须和改动前逐字一致。
    // 到 8/24 共结算 4 天（21/22/23/24），每天 10 元。
    func testHoldingWithoutRateAdjustmentsBehavesAsBefore() {
        let holding = interestHolding(rate: 36.5, mode: .simple)

        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: milliseconds("2026-08-24T08:00:00Z")),
            40,
            accuracy: 0.000_001
        )
    }

    // 复利跨利率段时，累计利息要连续滚下去，不能在切段处重置。
    func testCompoundInterestCarriesAccrualAcrossRateSegments() {
        var holding = interestHolding(rate: 36.5, mode: .compound)
        holding.rateAdjustments = [
            RateAdjustment(
                id: "r1",
                annualRate: 18.25,
                date: "2026-08-23",
                createdAt: milliseconds("2026-08-23T00:00:00Z")
            )
        ]

        // 21、22 两天按 0.1% 复利：利息 = 10000*(1.001^2) - 10000。
        // 23、24 两天按 0.05% 继续在「本金+已累计利息」上滚，且累计额要延续
        // 而不是从零重来 —— 这正是切段后最容易写错的地方。
        let firstSegment: Double = 10_000 * pow(1.001 as Double, 2) - 10_000
        let expected: Double = (10_000 + firstSegment) * pow(1.0005 as Double, 2) - 10_000

        XCTAssertEqual(
            HoldingValuation.accruedInterest(for: holding, at: milliseconds("2026-08-24T08:00:00Z")),
            expected,
            accuracy: 0.000_001
        )
    }

    // effectiveAnnualRate 是「当前利率」的唯一入口，展示层都该走它。
    func testEffectiveAnnualRatePicksLatestApplicableChange() {
        var holding = interestHolding(rate: 36.5, mode: .simple)
        holding.rateAdjustments = [
            RateAdjustment(id: "r1", annualRate: 18.25, date: "2026-08-23", createdAt: 1),
            RateAdjustment(id: "r2", annualRate: 9.0, date: "2026-09-01", createdAt: 2)
        ]

        let rate = { (iso: String) in
            HoldingValuation.effectiveAnnualRate(for: holding, at: self.milliseconds(iso))
        }
        XCTAssertEqual(rate("2026-08-22T08:00:00Z"), 36.5, "变更前用初始利率")
        XCTAssertEqual(rate("2026-08-23T08:00:00Z"), 18.25, "生效当天即采用新利率")
        XCTAssertEqual(rate("2026-08-31T08:00:00Z"), 18.25, "下一条尚未生效")
        XCTAssertEqual(rate("2026-09-02T08:00:00Z"), 9.0, "取最后一条已生效的")
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
