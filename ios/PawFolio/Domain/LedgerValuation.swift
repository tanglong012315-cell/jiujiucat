import Foundation

struct LedgerPortfolioSummary: Equatable, Sendable {
    let totalValueUSD: Double?
    let contributedCapitalUSD: Double?
    let profitUSD: Double?
    let profitPercent: Double?
    let historyUSD: [Double]
    let missingAssetCodes: Set<String>

    static let empty = Self(
        totalValueUSD: 0,
        contributedCapitalUSD: 0,
        profitUSD: 0,
        profitPercent: nil,
        historyUSD: [],
        missingAssetCodes: []
    )
}

/// 资产走势图的统一可见性规则。零资产、估值未知、样本不足或坏数据都不应伪装成
/// 一条有意义的趋势；这些状态直接留空。
enum LedgerPortfolioChartPolicy {
    static func shouldShow(totalValueUSD: Double?, values: [Double]) -> Bool {
        guard let totalValueUSD,
              totalValueUSD.isFinite,
              totalValueUSD > LedgerEntry.balanceTolerance,
              values.count >= 2 else {
            return false
        }
        return values.allSatisfy(\.isFinite)
    }
}

extension LedgerAsset {
    var marketQuoteSymbol: String? {
        switch kind {
        case .cryptocurrency:
            return code.hasSuffix("-USD") ? code : "\(code)-USD"
        case .equity, .etf:
            return code
        case .stablecoin:
            // 稳定币过去不取行情、一律按 1 美元算。但 1 USDT 不等于 1 美元
            // （实测 0.9998），持有几万 USDT 时那点差价是真金白银。
            // 交易所有真实的美元现货盘（USDTUSD / USDCUSD），取得到就用真的。
            return code
        case .fiat:
            return nil
        }
    }
}

enum LedgerValuation {
    static func summary(
        entries: [LedgerEntry],
        projection: LedgerProjection,
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        asOf date: Date = Date()
    ) -> LedgerPortfolioSummary {
        var missing: Set<String> = []
        let total = value(
            balances: projection.balances,
            quotes: quotes,
            exchangeRates: exchangeRates,
            at: nil,
            missing: &missing
        )
        let contributed = contributedCapital(
            entries: entries,
            quotes: quotes,
            exchangeRates: exchangeRates,
            missing: &missing
        )
        let profit = total.flatMap { total in contributed.map { total - $0 } }
        let percent = profit.flatMap { profit in
            contributed.flatMap { abs($0) > LedgerEntry.balanceTolerance ? profit / $0 * 100 : nil }
        }
        var history = history(
            entries: entries,
            quotes: quotes,
            exchangeRates: exchangeRates,
            asOf: date
        )
        // A quote series can lag its headline price. The chart still needs to
        // terminate at the exact total shown above it.
        if let total, !history.isEmpty {
            history[history.count - 1] = total
        }
        return LedgerPortfolioSummary(
            totalValueUSD: total,
            contributedCapitalUSD: contributed,
            profitUSD: profit,
            profitPercent: percent,
            historyUSD: history,
            missingAssetCodes: missing
        )
    }

    static func requiredQuoteSymbols(for projection: LedgerProjection) -> Set<String> {
        Set(projection.balances.compactMap { key, quantity in
            guard key.account.isUserControlled,
                  quantity > LedgerEntry.balanceTolerance else { return nil }
            return key.asset.marketQuoteSymbol
        })
    }

    private static func value(
        balances: [LedgerBalanceKey: Double],
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        at timestampMilliseconds: TimeInterval?,
        missing: inout Set<String>
    ) -> Double? {
        var total = 0.0
        for (key, quantity) in balances where key.account.isUserControlled && quantity > LedgerEntry.balanceTolerance {
            guard let unitValue = unitValueUSD(
                for: key.asset,
                quotes: quotes,
                exchangeRates: exchangeRates,
                at: timestampMilliseconds
            ) else {
                missing.insert(key.asset.code)
                continue
            }
            total += quantity * unitValue
        }
        return missing.isEmpty ? total : nil
    }

    private static func contributedCapital(
        entries: [LedgerEntry],
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        missing: inout Set<String>
    ) -> Double? {
        var capital = 0.0
        let reversed = Set(entries.compactMap { $0.kind == .reversal ? $0.reversesEntryID : nil })
        for entry in entries where entry.kind != .reversal && !reversed.contains(entry.id) {
            switch entry.kind {
            case .deposit, .expense:
                guard let posting = entry.primaryUserPosting,
                      let unit = unitValueUSD(for: posting.asset, quotes: quotes, exchangeRates: exchangeRates, at: nil) else {
                    if let code = entry.primaryUserPosting?.asset.code { missing.insert(code) }
                    continue
                }
                capital += posting.quantity * unit
            case .openingBalance:
                guard let posting = entry.primaryUserPosting else { continue }
                if let unitCost = entry.openingUnitCost {
                    capital += posting.quantity * unitCost
                } else if let unit = unitValueUSD(for: posting.asset, quotes: quotes, exchangeRates: exchangeRates, at: nil) {
                    capital += posting.quantity * unit
                } else {
                    missing.insert(posting.asset.code)
                }
            case .buy, .sell, .earnSubscribe, .earnRedeem, .interest, .reversal:
                break
            }
        }
        return missing.isEmpty ? capital : nil
    }

    private static func history(
        entries: [LedgerEntry],
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        asOf date: Date
    ) -> [Double] {
        guard !entries.isEmpty else { return [] }
        let earliest = entries.map(\.occurredAt).min() ?? date
        let start = max(earliest, date.addingTimeInterval(-30 * 24 * 60 * 60))
        let span = max(1, date.timeIntervalSince(start))
        return (0..<12).compactMap { index in
            let pointDate = start.addingTimeInterval(span * Double(index) / 11)
            guard let projection = try? LedgerProjection(entries: entries.filter { $0.occurredAt <= pointDate }) else {
                return nil
            }
            var missing: Set<String> = []
            return value(
                balances: projection.balances,
                quotes: quotes,
                exchangeRates: exchangeRates,
                at: pointDate.timeIntervalSince1970 * 1_000,
                missing: &missing
            )
        }
    }

    /// 展开态那张大图（设计 `197:2922`）：按 1D/1W/1M/1Y 取一段，点上带时间戳，
    /// 好让两端的坐标标注和长按扫描报得出时刻。收起态跟在总资产右边的迷你曲线
    /// 仍走 `summary` 里那 12 个点，两条互不影响。
    static func series(
        entries: [LedgerEntry],
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        range: PortfolioHistoryRange,
        asOf date: Date = Date()
    ) -> [PortfolioHistoryPoint] {
        guard !entries.isEmpty else { return [] }
        let end = date.timeIntervalSince1970 * 1_000
        // 建账之前那一段恒为 0，画出来是一条贴着底边的长横线。起点跟着第一笔
        // 分录走，这样只有一个月流水时切到 1Y 也不会先躺一大段 0。
        let earliest = (entries.map(\.occurredAt).min() ?? date).timeIntervalSince1970 * 1_000
        let start = max(earliest, end - range.spanMilliseconds)
        let span = max(1, end - start)
        return (0..<seriesSampleCount).compactMap { index in
            let timestamp = start + span * Double(index) / Double(seriesSampleCount - 1)
            let pointDate = Date(timeIntervalSince1970: timestamp / 1_000)
            guard let projection = try? LedgerProjection(
                entries: entries.filter { $0.occurredAt <= pointDate }
            ) else { return nil }
            var missing: Set<String> = []
            guard let value = value(
                balances: projection.balances,
                quotes: quotes,
                exchangeRates: exchangeRates,
                at: timestamp,
                missing: &missing
            ) else { return nil }
            return PortfolioHistoryPoint(timestampMilliseconds: timestamp, value: value)
        }
    }

    /// 取样数不跟 `PortfolioHistoryRange.sampleCount`（48～183）：那套数是给
    /// 「一次算好整条价格序列再乘数量」的持仓图用的，账本这边每个采样点都要
    /// 重放一遍分录再估值。48 个点铺满 343pt 宽已经是 7pt 一格，够密了。
    static let seriesSampleCount = 48

    static func unitValueUSD(
        for asset: LedgerAsset,
        quotes: [String: MarketQuote],
        exchangeRates: ExchangeRateSnapshot?,
        at timestampMilliseconds: TimeInterval?
    ) -> Double? {
        switch asset.kind {
        case .stablecoin:
            // 取到真实现价就用真的；取不到（长尾稳定币没有盘口、或行情服务挂了）
            // 退回 1:1，也就是改造前的行为。绝不拿一个猜的汇率去算钱。
            guard let symbol = asset.marketQuoteSymbol,
                  let quote = quotes[symbol] ?? quotes[asset.code],
                  quote.price.isFinite,
                  quote.price > 0 else { return 1 }
            return quote.price
        case .fiat:
            if asset.code == "USD" { return 1 }
            guard let rate = exchangeRates?.ratesPerUSD[CurrencyCode(asset.code)], rate > 0 else { return nil }
            return 1 / rate
        case .cryptocurrency, .equity, .etf:
            guard let symbol = asset.marketQuoteSymbol,
                  let quote = quotes[symbol] ?? quotes[asset.code] else { return nil }
            guard let timestampMilliseconds else { return quote.price }
            return quote.series
                .filter { $0.timestampMilliseconds <= timestampMilliseconds }
                .max(by: { $0.timestampMilliseconds < $1.timestampMilliseconds })?
                .price ?? quote.series.min(by: {
                    $0.timestampMilliseconds < $1.timestampMilliseconds
                })?.price ?? quote.price
        }
    }
}
