import Foundation

/// 「合并同资产」时一组持仓的汇总，对应 `app.js` 的 `mergedHoldingModel`。
///
/// 这里几处刻意为空的字段都出自同一条原则：**合并后不确定的东西就不显示**。
/// 几笔年化不同却挑一个当代表，是谎报；计息方式不同写成「稳定生息」，是废话。
struct MergedHoldingSummary: Equatable, Sendable {
    let symbol: String
    let quoteSymbol: String
    let name: String
    let assetType: AssetType?
    /// 这一组有几笔。
    let count: Int
    let totalCost: Double
    /// 组内任意一笔缺行情，合计就不给——半个合计比没有更容易误读。
    let totalValue: Double?
    let totalProfit: Double?
    let profitPercent: Double
    /// 副标题：全生息给总成本，全市场类给总份数，混合给「综合成本」。
    let detail: String
    /// 全组年化一致且大于 0 时才有。
    let rateTag: String?
    /// 全组计息方式一致时才有（单利／复利）。
    let interestModeTag: String?
    /// 全是生息持仓时，盈亏一栏其实是利息。
    let profitLabel: String

    var hasValue: Bool { totalValue != nil }
}

/// 合并组里生息持仓的利息小结，对应 `app.js` 的 `interestSettlementSummary`。
struct MergedInterestSummary: Equatable, Sendable {
    let daily: Double
    let last: Double
    let total: Double

    var isEmpty: Bool { daily == 0 && last == 0 && total == 0 }
}

enum HoldingMerging {
    /// 按标的代码分组，保持首次出现的顺序。代码统一去空白并转大写。
    static func groups(for holdings: [Holding]) -> [(symbol: String, holdings: [Holding])] {
        var order: [String] = []
        var grouped: [String: [Holding]] = [:]

        for holding in holdings {
            let key = holding.symbol.trimmingCharacters(in: .whitespaces).uppercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(holding)
        }

        return order.compactMap { key in
            guard let group = grouped[key] else { return nil }
            return (symbol: key, holdings: group)
        }
    }

    static func summary(
        for group: [Holding],
        metrics: (Holding) -> HoldingMetrics
    ) -> MergedHoldingSummary? {
        guard let first = group.first else { return nil }

        let all = group.map(metrics)
        let totalCost = all.reduce(0) { $0 + $1.cost }
        let totalValue = all.allSatisfy(\.hasValue)
            ? all.reduce(0) { $0 + ($1.value ?? 0) }
            : nil
        let totalProfit = all.allSatisfy { $0.profit != nil }
            ? all.reduce(0) { $0 + ($1.profit ?? 0) }
            : nil

        let marketMetrics = all.filter { $0.kind != .interest }
        let totalQuantity = marketMetrics.reduce(0) { $0 + $1.quantity }
        let allStable = all.allSatisfy { $0.kind == .interest }
        let allMarketBased = marketMetrics.count == all.count

        let detail: String
        if allStable {
            detail = money(totalCost)
        } else if allMarketBased, totalQuantity > 0 {
            detail = "\(totalQuantity.formatted(.number.precision(.fractionLength(0...6)))) 份"
        } else {
            detail = "综合成本 \(money(totalCost))"
        }

        // 年化只有全组一致时才敢标。
        let rates = Set(group.filter { $0.holdingKind == .interest }.map { $0.annualRate ?? 0 })
        let rateTag: String? = {
            guard allStable, rates.count == 1, let rate = rates.first, rate > 0 else { return nil }
            return rate.formatted(.number.precision(.fractionLength(2))) + "%"
        }()

        let interestModeTag: String? = {
            guard allStable else { return nil }
            if group.allSatisfy({ $0.interestMode == .compound }) { return "复利" }
            if group.allSatisfy({ $0.interestMode != .compound }) { return "单利" }
            return nil
        }()

        return MergedHoldingSummary(
            symbol: first.symbol,
            quoteSymbol: first.quoteSymbol,
            name: first.name,
            assetType: first.assetType,
            count: group.count,
            totalCost: totalCost,
            totalValue: totalValue,
            totalProfit: totalProfit,
            profitPercent: totalCost > 0 ? ((totalProfit ?? 0) / totalCost * 100) : 0,
            detail: detail,
            rateTag: rateTag,
            interestModeTag: interestModeTag,
            profitLabel: allStable ? "利息" : "盈亏"
        )
    }

    /// 合并卡本身只有一个总数，展开后要在子行上面补这一组的利息小结——
    /// 单笔的三个数在各自的明细里，合并后的没地方看。
    static func interestSummary(
        for group: [Holding],
        at timestampMilliseconds: TimeInterval
    ) -> MergedInterestSummary? {
        let interestHoldings = group.filter { $0.holdingKind == .interest || $0.holdingKind == .hybrid }
        guard !interestHoldings.isEmpty else { return nil }

        let daily = interestHoldings.reduce(0.0) { sum, holding in
            sum + (HoldingValuation.nextInterestSettlement(
                for: holding,
                at: timestampMilliseconds
            )?.amount ?? 0)
        }
        let last = interestHoldings.reduce(0.0) { sum, holding in
            sum + (HoldingValuation.lastInterestSettlement(
                for: holding,
                at: timestampMilliseconds
            )?.amount ?? 0)
        }
        let total = interestHoldings.reduce(0.0) { sum, holding in
            sum + HoldingValuation.accruedInterest(for: holding, at: timestampMilliseconds)
        }

        return MergedInterestSummary(daily: daily, last: last, total: total)
    }

    private static func money(_ amount: Double) -> String {
        "$" + amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }
}
