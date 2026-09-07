import Foundation

/// 汇率页记在本地的两样东西：用户自己攒的币种列表，和最近一次汇率快照。
protocol ExchangeRatePreferencesStoring: Sendable {
    func loadSelection() -> [CurrencyCode]?
    func save(selection: [CurrencyCode])
    func loadSnapshot() -> ExchangeRateSnapshot?
    func save(snapshot: ExchangeRateSnapshot)
}

/// 持仓页记在本地的偏好。
protocol PortfolioPreferencesStoring: Sendable {
    func loadHistoryRange() -> PortfolioHistoryRange?
    func save(historyRange: PortfolioHistoryRange)
    func loadSpotAssetOrder() -> [LedgerAsset]
    func save(spotAssetOrder: [LedgerAsset])
    func loadTradingAssetOrder() -> [LedgerAsset]
    func save(tradingAssetOrder: [LedgerAsset])
    func loadEarnProductOrder() -> [String]
    func save(earnProductOrder: [String])
}

/// Keep lightweight test and preview stores source-compatible while the concrete
/// UserDefaults store persists all three orderings.
extension PortfolioPreferencesStoring {
    func loadTradingAssetOrder() -> [LedgerAsset] { [] }
    func save(tradingAssetOrder: [LedgerAsset]) {}
    func loadEarnProductOrder() -> [String] { [] }
    func save(earnProductOrder: [String]) {}
}

/// `UserDefaults` 的落地实现。
///
/// 这两个协议是 V1.2.0 质量审计的产物：在此之前，币种列表、汇率快照和走势图区间
/// 的读写都写在 `Features/` 的 ViewModel 里，既违反了 `AGENTS.md`「本地存储走
/// repository 边界」的约束，也让 `PortfolioViewModel` 因为硬编码
/// `UserDefaults.standard` 而**根本没法注入测试沙盒**——它 700 行至今零测试就是
/// 这么来的。
///
/// 读写是同步的：两个 ViewModel 都要在 `init` 里恢复状态，actor 化会把 `init`
/// 逼成异步，界面首帧就得先闪一下空列表。
///
/// `@unchecked Sendable` 的依据是 `UserDefaults` 自身「线程安全」的文档承诺——
/// 它只是没有被标注成 `Sendable`。本类型除此之外没有可变状态。
struct UserDefaultsPreferencesStore: ExchangeRatePreferencesStoring,
                                     PortfolioPreferencesStoring,
                                     @unchecked Sendable {
    private enum Key {
        static let currencySelection = "pawfolio.exchange-rate.currencies.v1"
        static let exchangeRateSnapshot = "pawfolio.exchange-rate.snapshot.v2"
        static let historyRange = "pawfolio.portfolio.history-range"
        static let spotAssetOrder = "pawfolio.portfolio.spot-asset-order.v1"
        static let tradingAssetOrder = "pawfolio.portfolio.trading-asset-order.v1"
        static let earnProductOrder = "pawfolio.portfolio.earn-product-order.v1"
        /// V1.2.0 之前这个 key 漏了 `pawfolio.` 前缀，和其余六个不是一套。
        /// 改名要带迁移，否则老用户已经选好的区间会静默丢掉。
        static let legacyHistoryRange = "portfolio.historyRange"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 汇率

    func loadSelection() -> [CurrencyCode]? {
        guard let stored = defaults.array(forKey: Key.currencySelection) as? [String] else {
            return nil
        }
        return stored.map(CurrencyCode.init(rawValue:))
    }

    func save(selection: [CurrencyCode]) {
        defaults.set(selection.map(\.rawValue), forKey: Key.currencySelection)
    }

    func loadSnapshot() -> ExchangeRateSnapshot? {
        guard let data = defaults.data(forKey: Key.exchangeRateSnapshot) else { return nil }
        return try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data)
    }

    func save(snapshot: ExchangeRateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.exchangeRateSnapshot)
    }

    // MARK: - 持仓

    func loadHistoryRange() -> PortfolioHistoryRange? {
        if let raw = defaults.string(forKey: Key.historyRange) {
            return PortfolioHistoryRange(rawValue: raw)
        }

        // 迁移：把旧 key 的值搬到新 key 上，搬完就把旧的清掉。
        guard let legacy = defaults.string(forKey: Key.legacyHistoryRange),
              let range = PortfolioHistoryRange(rawValue: legacy) else {
            return nil
        }
        defaults.set(legacy, forKey: Key.historyRange)
        defaults.removeObject(forKey: Key.legacyHistoryRange)
        return range
    }

    func save(historyRange: PortfolioHistoryRange) {
        defaults.set(historyRange.rawValue, forKey: Key.historyRange)
    }

    func loadSpotAssetOrder() -> [LedgerAsset] {
        guard let data = defaults.data(forKey: Key.spotAssetOrder) else { return [] }
        guard let decoded = try? JSONDecoder().decode([LedgerAsset].self, from: data) else { return [] }
        var seen: Set<LedgerAsset> = []
        return decoded.filter { seen.insert($0).inserted }
    }

    func save(spotAssetOrder: [LedgerAsset]) {
        guard let data = try? JSONEncoder().encode(spotAssetOrder) else { return }
        defaults.set(data, forKey: Key.spotAssetOrder)
    }

    func loadTradingAssetOrder() -> [LedgerAsset] {
        guard let data = defaults.data(forKey: Key.tradingAssetOrder),
              let decoded = try? JSONDecoder().decode([LedgerAsset].self, from: data) else {
            return []
        }
        var seen: Set<LedgerAsset> = []
        return decoded.filter { seen.insert($0).inserted }
    }

    func save(tradingAssetOrder: [LedgerAsset]) {
        guard let data = try? JSONEncoder().encode(tradingAssetOrder) else { return }
        defaults.set(data, forKey: Key.tradingAssetOrder)
    }

    func loadEarnProductOrder() -> [String] {
        guard let decoded = defaults.stringArray(forKey: Key.earnProductOrder) else { return [] }
        var seen: Set<String> = []
        return decoded.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func save(earnProductOrder: [String]) {
        defaults.set(earnProductOrder, forKey: Key.earnProductOrder)
    }
}
