import XCTest
@testable import PawFolio

final class InvestmentCalculatorTests: XCTestCase {
    func testCompoundSummaryMatchesWebReference() {
        let input = InvestmentInput(
            principal: 10_000,
            annualRatePercent: 8,
            mode: .compound
        )

        let result = InvestmentCalculator.summary(for: input)

        XCTAssertEqual(result.dailyProfit, 2.1087439837685906, accuracy: 0.000_001)
        XCTAssertEqual(
            result.weeklyProfit,
            10_000 * (pow(1.08, 7.0 / 365.0) - 1),
            accuracy: 0.000_001
        )
        XCTAssertEqual(result.monthlyProfit, 64.34030110003431, accuracy: 0.000_001)
        XCTAssertEqual(result.yearlyProfit, 800, accuracy: 0.000_001)
    }

    func testSimpleSummaryUsesLinearGrowth() {
        let input = InvestmentInput(
            principal: 10_000,
            annualRatePercent: 8,
            mode: .simple
        )

        let result = InvestmentCalculator.summary(for: input)

        XCTAssertEqual(result.dailyProfit, 10_000 * 0.08 / 365, accuracy: 0.000_001)
        XCTAssertEqual(result.weeklyProfit, 10_000 * 0.08 * 7 / 365, accuracy: 0.000_001)
        XCTAssertEqual(result.monthlyProfit, 10_000 * 0.08 / 12, accuracy: 0.000_001)
        XCTAssertEqual(result.yearlyProfit, 800, accuracy: 0.000_001)
    }

    func testForecastRangesMatchWebSampleCounts() {
        let input = InvestmentInput(
            principal: 10_000,
            annualRatePercent: 8,
            mode: .compound
        )

        XCTAssertEqual(InvestmentCalculator.forecast(for: input, period: .day).count, 366)
        XCTAssertEqual(InvestmentCalculator.forecast(for: input, period: .month).count, 37)
        XCTAssertEqual(InvestmentCalculator.forecast(for: input, period: .year).count, 13)
    }

    func testTwelveYearForecastEndsAtExpectedCompoundAmount() throws {
        let input = InvestmentInput(
            principal: 10_000,
            annualRatePercent: 8,
            mode: .compound
        )

        let finalPoint = try XCTUnwrap(
            InvestmentCalculator.forecast(for: input, period: .year).last
        )

        XCTAssertEqual(finalPoint.years, 12)
        XCTAssertEqual(finalPoint.amount, 10_000 * pow(1.08, 12), accuracy: 0.000_001)
    }

    func testInvalidInputIsSanitizedLikeWebForm() {
        let input = InvestmentInput(
            principal: -Double.infinity,
            annualRatePercent: -Double.infinity,
            mode: .simple
        )

        XCTAssertEqual(input.sanitized.principal, 1)
        XCTAssertEqual(input.sanitized.annualRatePercent, 0)
    }

    /// 结果区第二行：年 / 5 年 / 10 年收益。单利按本金线性累加，
    /// 复利按年复利，两条路径都钉一下，免得以后改公式时只有短周期被覆盖。
    func testSummaryCoversOneFiveAndTenYears() {
        let simple = InvestmentCalculator.summary(
            for: InvestmentInput(principal: 100_000, annualRatePercent: 8, mode: .simple)
        )
        XCTAssertEqual(simple.yearlyProfit, 8_000, accuracy: 0.01)
        XCTAssertEqual(simple.fiveYearProfit, 40_000, accuracy: 0.01)
        XCTAssertEqual(simple.tenYearProfit, 80_000, accuracy: 0.01)

        let compound = InvestmentCalculator.summary(
            for: InvestmentInput(principal: 100_000, annualRatePercent: 8, mode: .compound)
        )
        XCTAssertEqual(compound.fiveYearProfit, 100_000 * (pow(1.08, 5) - 1), accuracy: 0.01)
        XCTAssertEqual(compound.tenYearProfit, 100_000 * (pow(1.08, 10) - 1), accuracy: 0.01)
        XCTAssertGreaterThan(compound.tenYearProfit, simple.tenYearProfit)
    }

}
