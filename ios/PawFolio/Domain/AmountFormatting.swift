import Foundation

/// 金额数字的唯一格式化实现。
///
/// 在 V1.2.0 的质量审计之前，同一条规则（千分位 + 固定两位小数）在
/// `PortfolioView`、`PortfolioHistoryCard`、`HoldingGrouping`、`HoldingEditorView`、
/// `CalculatorView` 里各写了一遍。改一处改不到其余四处，这里收成一份。
///
/// 带符号的写法也在这里。2026-09-03 的审计发现走势图卡片那份**负数不显示负号**
/// （`-5` 渲染成 `$5`），和列表那份不一致；用户确认负号要显示，两处遂并成一份。
enum MoneyFormat {
    /// 千分位 + 固定小数位。
    static func decimal(_ amount: Double, fractionDigits: Int = 2) -> String {
        amount.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(fractionDigits))
        )
    }

    /// `$1,234.56`。Web 一律写 `$`，不是 iOS 本地化出来的 `US$`。
    static func dollars(_ amount: Double) -> String {
        "$" + decimal(amount)
    }

    /// `1,234.56 USD`。
    static func usd(_ amount: Double) -> String {
        decimal(amount) + " USD"
    }

    /// `12.34%`。负号由数字自带，这里不额外补。
    static func percent(_ value: Double) -> String {
        decimal(value) + "%"
    }

    /// `+$1,234.56` / `-$1,234.56`，0 不带符号。
    static func signedDollars(_ amount: Double) -> String {
        sign(of: amount) + dollars(abs(amount))
    }

    /// `+1,234.56` / `-1,234.56`，0 不带符号。
    static func signedDecimal(_ amount: Double) -> String {
        sign(of: amount) + decimal(abs(amount))
    }

    private static func sign(of amount: Double) -> String {
        if amount > 0 { return "+" }
        if amount < 0 { return "-" }
        return ""
    }
}

/// 可编辑金额输入框的解析与回填。
///
/// 同样是审计前散在五处的规则：去掉用户或格式化留下的千分位逗号、去掉首尾空白、
/// 再交给 `Double`。
///
/// **只做归一化，不做校验。** 解析失败回落成什么（计算器是 `?? 1`）、允不允许负数、
/// 要不要挡住 `inf`（汇率页要），各调用点的语义本来就不一样，那些判断留在调用点，
/// 别塞进来——塞进来就得给每个调用点开一个参数，等于把分叉换了个地方放。
enum AmountInput {
    static func parse(_ text: String) -> Double? {
        Double(
            text
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 回填进输入框的写法：**不带**千分位（否则光标一动就要重新解析），
    /// 最多 8 位小数，`nil` 回空串。
    static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...8))
        )
    }
}
