import XCTest
@testable import PawFolio

/// 这一组是**性征测试**：合并五处重复实现之前先把当时的行为钉住，合并之后必须
/// 一条不改地继续通过。
///
/// 断言写成「结构」而不是「某个具体字符串」，是因为 `.formatted` 的千分位和小数点
/// 跟随 `Locale.current`：写死 `"$1,234.56"` 会在非英语区的机器上误报。产品代码
/// 本来就是跟随 locale 的，这里也就不去锁它。
final class MoneyFormatTests: XCTestCase {
    private func fractionDigits(_ text: String) -> Int {
        let separator = Locale.current.decimalSeparator ?? "."
        guard let range = text.range(of: separator, options: .backwards) else { return 0 }
        return text[range.upperBound...].filter(\.isNumber).count
    }

    func testDecimalKeepsTwoFractionDigitsAndGroupsThousands() {
        let text = MoneyFormat.decimal(1_234.5)

        XCTAssertEqual(fractionDigits(text), 2)
        // 千分位一定在：这正是 `.grouping(.automatic)` 和输入框那份
        // `.grouping(.never)` 的区别所在。
        XCTAssertTrue(
            text.contains(Locale.current.groupingSeparator ?? ","),
            text
        )
    }

    func testDecimalCanDropTheFractionEntirely() {
        XCTAssertEqual(fractionDigits(MoneyFormat.decimal(1_234.5, fractionDigits: 0)), 0)
    }

    func testDecimalRoundsRatherThanTruncates() {
        XCTAssertEqual(MoneyFormat.decimal(1.006), MoneyFormat.decimal(1.01))
        XCTAssertEqual(MoneyFormat.decimal(1.004), MoneyFormat.decimal(1.00))
        // 半分位不要拿来断言：`1.005` 的二进制表示比 1.005 略小，实际进位成 1.00。
        // 这是 `Double` 的性质，不是格式化的策略，改成十进制类型才有意义。
    }

    /// Web 一律写 `$`。iOS 的货币本地化会写成 `US$`，那是错的。
    func testDollarsUsesABareDollarSign() {
        let text = MoneyFormat.dollars(1_234.5)

        XCTAssertTrue(text.hasPrefix("$"), text)
        XCTAssertFalse(text.contains("US$"), text)
        XCTAssertEqual(String(text.dropFirst()), MoneyFormat.decimal(1_234.5))
    }

    func testUsdPutsTheCodeAfterTheNumber() {
        let text = MoneyFormat.usd(1_234.5)

        XCTAssertTrue(text.hasSuffix(" USD"), text)
        XCTAssertEqual(String(text.dropLast(4)), MoneyFormat.decimal(1_234.5))
    }

    func testPercentKeepsTwoFractionDigits() {
        let text = MoneyFormat.percent(12.3)

        XCTAssertTrue(text.hasSuffix("%"), text)
        XCTAssertEqual(fractionDigits(String(text.dropLast())), 2)
    }

    /// 2026-09-03 修的一个真 bug：走势图卡片那份 `signedCurrency` 用
    /// `dollars(abs(value))` 再只给正数补 `+`，于是 `-5` 渲染成 `$5`——涨跌看不出来。
    /// 用户确认负号必须显示，这里钉死。
    func testSignedFormsAlwaysCarryTheMinusSign() {
        XCTAssertTrue(MoneyFormat.signedDollars(-5).hasPrefix("-$"), MoneyFormat.signedDollars(-5))
        XCTAssertTrue(MoneyFormat.signedDecimal(-5).hasPrefix("-"), MoneyFormat.signedDecimal(-5))
    }

    func testSignedFormsAddAPlusForGains() {
        XCTAssertTrue(MoneyFormat.signedDollars(5).hasPrefix("+$"), MoneyFormat.signedDollars(5))
        XCTAssertTrue(MoneyFormat.signedDecimal(5).hasPrefix("+"), MoneyFormat.signedDecimal(5))
    }

    /// 持平不带符号：`+$0.00` 看着像涨了。
    func testSignedFormsLeaveZeroUnsigned() {
        XCTAssertEqual(MoneyFormat.signedDollars(0), MoneyFormat.dollars(0))
        XCTAssertEqual(MoneyFormat.signedDecimal(0), MoneyFormat.decimal(0))
    }

    /// 符号只加一次，不能出现 `--5`。
    func testSignedFormsDoNotDoubleUpTheSign() {
        XCTAssertFalse(MoneyFormat.signedDollars(-5).contains("--"))
        XCTAssertFalse(MoneyFormat.signedDecimal(-5).contains("--"))
    }

    func testNegativeAmountsKeepTheirOwnSign() {
        // 正负号归调用点管，格式化不吞也不加。
        XCTAssertTrue(MoneyFormat.decimal(-1).hasPrefix("-"), MoneyFormat.decimal(-1))
    }
}

final class AmountInputTests: XCTestCase {
    func testParseStripsGroupingCommasAndSurroundingSpace() {
        XCTAssertEqual(AmountInput.parse("1,234.5"), 1_234.5)
        XCTAssertEqual(AmountInput.parse("  12  "), 12)
        XCTAssertEqual(AmountInput.parse("1,000,000"), 1_000_000)
    }

    func testParseReturnsNilForEmptyAndGarbage() {
        XCTAssertNil(AmountInput.parse(""))
        XCTAssertNil(AmountInput.parse("   "))
        XCTAssertNil(AmountInput.parse("abc"))
        XCTAssertNil(AmountInput.parse("1.2.3"))
    }

    /// 归一化**不做校验**：负数和 `inf` 都照样解出来，挡不挡是调用点的事。
    /// 汇率页会另外要求 `isFinite` 且 `>= 0`，计算器则是解不出来就回落成 1。
    func testParseDoesNotValidateSignOrFiniteness() {
        XCTAssertEqual(AmountInput.parse("-5"), -5)
        XCTAssertEqual(AmountInput.parse("inf"), .infinity)
    }

    func testTextDropsGroupingSoTheFieldStaysEditable() {
        let text = AmountInput.text(1_234.5)

        XCTAssertFalse(text.contains(Locale.current.groupingSeparator ?? ","), text)
    }

    func testTextKeepsUpToEightFractionDigitsAndTrimsTrailingZeros() {
        XCTAssertEqual(AmountInput.text(2), AmountInput.text(2.0))
        XCTAssertFalse(AmountInput.text(2).contains(Locale.current.decimalSeparator ?? "."))

        let long = AmountInput.text(0.123_456_789)
        let separator = Locale.current.decimalSeparator ?? "."
        let fraction = long.range(of: separator).map { String(long[$0.upperBound...]) } ?? ""
        XCTAssertEqual(fraction.filter(\.isNumber).count, 8, long)
    }

    func testTextRendersNilAsAnEmptyField() {
        XCTAssertEqual(AmountInput.text(nil), "")
    }

    /// 输入框回填的值必须能再被解析回来，否则光标一动数值就变了。
    func testTextRoundTripsThroughParse() {
        for value in [0, 1, 1_234.5, 0.000_000_01, 987_654_321.25] as [Double] {
            XCTAssertEqual(AmountInput.parse(AmountInput.text(value)), value, "\(value)")
        }
    }
}
