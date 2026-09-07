import Combine
import Foundation

struct LedgerSpendableBalance: Equatable, Hashable, Identifiable, Sendable {
    let account: LedgerAccountReference
    let asset: LedgerAsset
    let quantity: Double

    var id: String { "\(account.kind.rawValue):\(account.identifier):\(asset.kind.rawValue):\(asset.code)" }
}

enum LedgerAccountLabelTonePolicy {
    static func usesPrimaryTone(isSelected: Bool, accountCount: Int) -> Bool {
        accountCount > 1 && isSelected
    }
}

@MainActor
final class LedgerPortfolioViewModel: ObservableObject {
    @Published private(set) var snapshot = LedgerStoreSnapshot()
    @Published private(set) var projection = LedgerProjection()
    @Published private(set) var quotes: [String: MarketQuote] = [:]
    @Published private(set) var exchangeRates: ExchangeRateSnapshot?
    @Published private(set) var portfolioSummary = LedgerPortfolioSummary.empty
    @Published private(set) var spotAssetOrder: [LedgerAsset]
    @Published private(set) var tradingAssetOrder: [LedgerAsset]
    @Published private(set) var earnProductOrder: [String]
    /// 展开态那张大图的区间与数据（设计 `197:2922`）。
    @Published private(set) var historyRange: PortfolioHistoryRange
    @Published private(set) var chartSeries: [PortfolioHistoryPoint] = []
    @Published private(set) var valuationStatusMessage: String?
    @Published private(set) var isLoading = true
    @Published private(set) var hasCompletedInitialLoad = false
    @Published var errorMessage: String?

    private let ledgerRepository: any ScopedLedgerRepository
    private let holdingRepository: any HoldingRepository
    private let scope: HoldingStorageScope
    private let quoteRepository: (any MarketQuoteRepositoryServing)?
    private let streamClient: MarketStreamClient?
    private var streamTask: Task<Void, Never>?
    private let exchangeRateClient: (any ExchangeRateServing)?
    private let preferences: (any ExchangeRatePreferencesStoring)?
    private let portfolioPreferences: (any PortfolioPreferencesStoring)?
    private var hasLoaded = false

    init(
        ledgerRepository: any ScopedLedgerRepository,
        holdingRepository: any HoldingRepository,
        scope: HoldingStorageScope,
        quoteRepository: (any MarketQuoteRepositoryServing)? = nil,
        streamClient: MarketStreamClient? = nil,
        exchangeRateClient: (any ExchangeRateServing)? = nil,
        preferences: (any ExchangeRatePreferencesStoring)? = nil,
        portfolioPreferences: (any PortfolioPreferencesStoring)? = nil
    ) {
        self.ledgerRepository = ledgerRepository
        self.holdingRepository = holdingRepository
        self.scope = scope
        self.quoteRepository = quoteRepository
        self.streamClient = streamClient
        self.exchangeRateClient = exchangeRateClient
        self.preferences = preferences
        self.portfolioPreferences = portfolioPreferences
        spotAssetOrder = portfolioPreferences?.loadSpotAssetOrder() ?? []
        tradingAssetOrder = portfolioPreferences?.loadTradingAssetOrder() ?? []
        earnProductOrder = portfolioPreferences?.loadEarnProductOrder() ?? []
        // 设计稿 `197:2922` 里选中的是 1D；上次选过就接着上次。
        historyRange = portfolioPreferences?.loadHistoryRange() ?? .day
    }

    var entries: [LedgerEntry] {
        snapshot.entries.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id > $1.id : $0.occurredAt > $1.occurredAt
        }
    }

    var spotBalances: [(asset: LedgerAsset, quantity: Double)] {
        var totals: [LedgerAsset: Double] = [:]
        for (key, quantity) in projection.balances where key.account.kind == .fiat {
            totals[key.asset, default: 0] += quantity
        }
        let balances: [(asset: LedgerAsset, quantity: Double)] = totals.compactMap { asset, quantity in
            quantity > LedgerEntry.balanceTolerance ? (asset, quantity) : nil
        }
        var ranks: [LedgerAsset: Int] = [:]
        for (index, asset) in spotAssetOrder.enumerated() where ranks[asset] == nil {
            ranks[asset] = index
        }
        return balances.sorted { lhs, rhs in
            switch (ranks[lhs.asset], ranks[rhs.asset]) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if lhs.asset.code == rhs.asset.code {
                    return lhs.asset.kind.rawValue < rhs.asset.kind.rawValue
                }
                return lhs.asset.code < rhs.asset.code
            }
        }
    }

    /// 只重排当前可见资产；暂时归零的资产仍保留在偏好末尾，日后重新入金不会完全
    /// 忘掉用户排过的位置。新出现的资产先按代码排序追加，第一次拖动后写入完整顺序。
    func moveSpotAsset(_ asset: LedgerAsset, to destination: Int) {
        var visible = spotBalances.map(\.asset)
        guard let origin = visible.firstIndex(of: asset),
              visible.indices.contains(destination),
              origin != destination else { return }

        visible.remove(at: origin)
        visible.insert(asset, at: destination)
        let visibleSet = Set(visible)
        spotAssetOrder = visible + spotAssetOrder.filter { !visibleSet.contains($0) }
        portfolioPreferences?.save(spotAssetOrder: spotAssetOrder)
    }

    var tradingBalances: [(asset: LedgerAsset, quantity: Double)] {
        let balances: [(asset: LedgerAsset, quantity: Double)] = projection.balances
            .filter { $0.key.account == .trading && $0.value > LedgerEntry.balanceTolerance }
            .map { ($0.key.asset, $0.value) }
        var ranks: [LedgerAsset: Int] = [:]
        for (index, asset) in tradingAssetOrder.enumerated() where ranks[asset] == nil {
            ranks[asset] = index
        }
        return balances.sorted { lhs, rhs in
            switch (ranks[lhs.asset], ranks[rhs.asset]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.asset.code < rhs.asset.code
            }
        }
    }

    var earnBalances: [(product: EarnProduct, quantity: Double)] {
        let balances: [(product: EarnProduct, quantity: Double)] = snapshot.earnProducts.compactMap { product in
            let quantity = projection.balance(in: .earn(productID: product.id), asset: product.asset)
            return quantity > LedgerEntry.balanceTolerance ? (product, quantity) : nil
        }
        var defaultRanks: [String: Int] = [:]
        for (index, product) in snapshot.earnProducts.enumerated() where defaultRanks[product.id] == nil {
            defaultRanks[product.id] = index
        }
        var ranks: [String: Int] = [:]
        for (index, id) in earnProductOrder.enumerated() where ranks[id] == nil {
            ranks[id] = index
        }
        return balances.sorted { lhs, rhs in
            switch (ranks[lhs.product.id], ranks[rhs.product.id]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return (defaultRanks[lhs.product.id] ?? .max) < (defaultRanks[rhs.product.id] ?? .max)
            }
        }
    }

    func moveTradingAsset(_ asset: LedgerAsset, to destination: Int) {
        var visible = tradingBalances.map(\.asset)
        guard let origin = visible.firstIndex(of: asset),
              visible.indices.contains(destination),
              origin != destination else { return }

        visible.remove(at: origin)
        visible.insert(asset, at: destination)
        let visibleSet = Set(visible)
        tradingAssetOrder = visible + tradingAssetOrder.filter { !visibleSet.contains($0) }
        portfolioPreferences?.save(tradingAssetOrder: tradingAssetOrder)
    }

    func moveEarnProduct(_ productID: String, to destination: Int) {
        var visible = earnBalances.map { $0.product.id }
        guard let origin = visible.firstIndex(of: productID),
              visible.indices.contains(destination),
              origin != destination else { return }

        visible.remove(at: origin)
        visible.insert(productID, at: destination)
        let visibleSet = Set(visible)
        earnProductOrder = visible + earnProductOrder.filter { !visibleSet.contains($0) }
        portfolioPreferences?.save(earnProductOrder: earnProductOrder)
    }

    var spendableBalances: [LedgerSpendableBalance] {
        projection.balances
            .compactMap { key, quantity in
                guard key.account.kind == .fiat,
                      quantity > LedgerEntry.balanceTolerance else { return nil }
                return LedgerSpendableBalance(account: key.account, asset: key.asset, quantity: quantity)
            }
            .sorted {
                if $0.asset.code == $1.asset.code {
                    return $0.account.identifier < $1.account.identifier
                }
                return $0.asset.code < $1.asset.code
            }
    }

    /// Earn products are persisted with a `LedgerAsset`, whose equality includes both the
    /// code and kind. Resolve the asset against the account that actually owns the balance
    /// before creating or subscribing to a product. This keeps a legacy USDG product that
    /// was stored as Crypto from missing the USDG balance in Fiat / Spot, while BTC still
    /// resolves to the Trading account.
    func preferredEarnAsset(
        code: String,
        fallbackKind: LedgerAsset.Kind
    ) -> LedgerAsset {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let canonicalKind: LedgerAsset.Kind
        if StablecoinCatalog.isKnown(normalizedCode) {
            canonicalKind = .stablecoin
        } else if CurrencyCatalog.contains(CurrencyCode(normalizedCode)) {
            canonicalKind = .fiat
        } else {
            canonicalKind = fallbackKind
        }

        let canonicalAsset = LedgerAsset(code: normalizedCode, kind: canonicalKind)
        let canonicalAccount = fundingAccount(for: canonicalAsset)
        let canonicalAccountAssets = positiveAssets(code: normalizedCode, in: canonicalAccount)
        if let exactAccountMatch = canonicalAccountAssets.first(where: { $0 == canonicalAsset })
            ?? canonicalAccountAssets.first {
            return exactAccountMatch
        }

        // Imported snapshots can contain a valid Earn asset with an older kind. Prefer the
        // real positive balance over an empty catalog-derived account, but only for kinds
        // that are allowed to enter Earn.
        if let anyAccountMatch = projection.balances
            .filter({ key, quantity in
                key.account.isUserControlled
                    && key.account.kind != .earn
                    && key.account == fundingAccount(for: key.asset)
                    && key.asset.code == normalizedCode
                    && key.asset.canEnterEarn
                    && quantity > LedgerEntry.balanceTolerance
            })
            .sorted(by: { lhs, rhs in
                if lhs.key.account.kind == rhs.key.account.kind {
                    return lhs.key.asset.kind.rawValue < rhs.key.asset.kind.rawValue
                }
                return lhs.key.account.kind.rawValue < rhs.key.account.kind.rawValue
            })
            .first?.key.asset {
            return anyAccountMatch
        }

        return canonicalAsset
    }

    /// Balance shown in the Subscribe sheet. Products created by builds that only knew
    /// USDT/USDC may carry the wrong kind, so a product with no prior ledger activity is
    /// resolved by code against the user's current Fiat / Spot or Trading balance.
    func availableBalance(for product: EarnProduct) -> Double {
        let storedProduct = snapshot.earnProducts.first(where: { $0.id == product.id }) ?? product
        let asset = correctedAssetIfSafe(for: storedProduct)
        return projection.balance(in: fundingAccount(for: asset), asset: asset)
    }

    func locationBalances(for asset: LedgerAsset) -> [(account: LedgerAccountReference, quantity: Double)] {
        projection.balances
            .filter {
                $0.key.account.kind == .fiat
                    && $0.key.asset == asset
                    && $0.value > LedgerEntry.balanceTolerance
            }
            .map { ($0.key.account, $0.value) }
            .sorted { $0.account.identifier < $1.account.identifier }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        defer {
            isLoading = false
            hasCompletedInitialLoad = true
        }
        do {
            let holdings = try await holdingRepository.load()
            snapshot = try await LedgerBootstrapService(repository: ledgerRepository).bootstrap(
                scope: scope,
                legacyHoldings: holdings,
                openingAt: Date()
            )
            projection = try LedgerProjection(entries: snapshot.entries)
            if let preferences { exchangeRates = preferences.loadSnapshot() }
            if let quoteRepository {
                quotes = await quoteRepository.cachedQuotes(
                    for: LedgerValuation.requiredQuoteSymbols(for: projection)
                )
            }
            recalculateSummary()
            await refreshValuation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accruedInterest(for product: EarnProduct, asOf date: Date = Date()) -> Double {
        (try? EarnInterestCalculator.accruedInterest(product: product, entries: snapshot.entries, asOf: date)) ?? 0
    }

    func effectiveRate(for product: EarnProduct, at date: Date = Date()) -> Double {
        product.annualRate(at: date)
    }

    func valueUSD(of asset: LedgerAsset, quantity: Double) -> Double? {
        LedgerValuation.unitValueUSD(
            for: asset,
            quotes: quotes,
            exchangeRates: exchangeRates,
            at: nil
        ).map { $0 * quantity }
    }

    /// 交易表单的 Buy Price / Sell Price 默认填最新价（设计 `159:19567` 的批注
    /// 「默认填入最新价」）。先看手上已有的行情——新选的标的多半不在持仓里，
    /// 这时才去仓库要；`refreshQuotes` 自己会落缓存，下次开表单就不必再联网。
    func latestPrice(for quoteSymbol: String) async -> Double? {
        let symbol = quoteSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return nil }
        if let price = quotes[symbol]?.price, price > 0 { return price }
        guard let quoteRepository else { return nil }
        if let price = await quoteRepository.cachedQuotes(for: [symbol])[symbol]?.price, price > 0 {
            return price
        }
        let price = await quoteRepository.refreshQuotes(for: [symbol]).quotes[symbol]?.price
        return (price ?? 0) > 0 ? price : nil
    }

    func tradingProfitUSD(for asset: LedgerAsset) -> Double? {
        guard let position = projection.tradingPositions[asset],
              let value = valueUSD(of: asset, quantity: position.quantity) else { return nil }
        return value - position.costBasis
    }

    func tradingProfitPercent(for asset: LedgerAsset) -> Double? {
        guard let position = projection.tradingPositions[asset],
              position.costBasis > LedgerEntry.balanceTolerance,
              let profit = tradingProfitUSD(for: asset) else { return nil }
        return profit / position.costBasis * 100
    }

    var totalTradingProfitUSD: Double? {
        let values = tradingBalances.map { tradingProfitUSD(for: $0.asset) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    var totalTradingProfitPercent: Double? {
        let cost = projection.tradingPositions.values.reduce(0) { $0 + $1.costBasis }
        guard cost > LedgerEntry.balanceTolerance, let profit = totalTradingProfitUSD else { return nil }
        return profit / cost * 100
    }

    func earnValueUSD(for product: EarnProduct, quantity: Double) -> Double? {
        valueUSD(of: product.asset, quantity: quantity)
    }

    func accruedInterestUSD(for product: EarnProduct) -> Double? {
        valueUSD(of: product.asset, quantity: accruedInterest(for: product))
    }

    func paidInterest(for product: EarnProduct, asOf date: Date = Date()) -> Double {
        EarnInterestCalculator.paidInterest(
            product: product,
            entries: snapshot.entries,
            asOf: date
        )
    }

    func paidInterestUSD(for product: EarnProduct, asOf date: Date = Date()) -> Double? {
        valueUSD(of: product.asset, quantity: paidInterest(for: product, asOf: date))
    }

    func dailyInterestUSD(for product: EarnProduct) -> Double? {
        let now = Date()
        let daily = EarnInterestCalculator.dailyInterest(
            product: product,
            principal: EarnInterestCalculator.interestBearingPrincipal(
                product: product,
                entries: snapshot.entries,
                asOf: now
            ),
            asOf: now
        )
        return valueUSD(of: product.asset, quantity: daily)
    }

    /// Holding 页汇总条的「Daily (USD)」：所有持仓一天的利息，按注释「这里统一换算成USD」折算。
    var totalEarnDailyInterestUSD: Double? {
        let values = earnBalances.map { dailyInterestUSD(for: $0.product) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    /// Earn summary total: interest that has reached Spot or Earn through an
    /// actual payout entry. It intentionally excludes the live accrual shown on
    /// individual holding rows before the next payout time.
    var totalEarnPaidInterestUSD: Double? {
        let values = earnBalances.map { paidInterestUSD(for: $0.product) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    func deposit(asset: LedgerAsset, quantity: Double, location: String, note: String?) async -> Bool {
        return await append {
            try LedgerEntry.deposit(
                asset: asset,
                quantity: quantity,
                into: location,
                occurredAt: Date(),
                note: note
            )
        }
    }

    func pay(asset: LedgerAsset, quantity: Double, location: String, note: String?) async -> Bool {
        return await append {
            try LedgerEntry.expense(
                asset: asset,
                quantity: quantity,
                from: location,
                occurredAt: Date(),
                note: note
            )
        }
    }

    func buy(
        asset: LedgerAsset,
        quantity: Double,
        unitPrice: Double,
        settlementAsset: LedgerAsset,
        fee: Double,
        note: String?
    ) async -> Bool {
        return await append {
            try LedgerEntry.buy(
                asset: asset,
                quantity: quantity,
                unitPrice: unitPrice,
                settlementAsset: settlementAsset,
                fee: fee,
                occurredAt: Date(),
                note: note
            )
        }
    }

    func sell(
        asset: LedgerAsset,
        quantity: Double,
        unitPrice: Double,
        settlementAsset: LedgerAsset,
        fee: Double,
        note: String?
    ) async -> Bool {
        await append {
            try LedgerEntry.sell(
                asset: asset,
                quantity: quantity,
                unitPrice: unitPrice,
                settlementAsset: settlementAsset,
                fee: fee,
                occurredAt: Date(),
                note: note
            )
        }
    }

    func createProduct(_ product: EarnProduct) async -> Bool {
        do {
            try product.validate()
            guard !snapshot.earnProducts.contains(where: { $0.id == product.id }) else {
                throw LedgerViewModelError.duplicateProduct
            }
            var candidate = snapshot
            candidate.earnProducts.append(product)
            try await ledgerRepository.save(candidate, for: scope)
            snapshot = candidate
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateProduct(_ product: EarnProduct) async -> Bool {
        do {
            try product.validate()
            guard let index = snapshot.earnProducts.firstIndex(where: { $0.id == product.id }) else {
                throw LedgerViewModelError.unknownProduct
            }
            var candidate = snapshot
            var scheduled = candidate.earnProducts[index]
            if abs(scheduled.annualRatePercent - product.annualRatePercent) > LedgerEntry.balanceTolerance {
                let effectiveAt = scheduled.nextPayout(after: Date()) ?? Date()
                try scheduled.scheduleAnnualRate(product.annualRatePercent, effectiveAt: effectiveAt)
            }
            // APY 走排期（下个付息点生效），名字这类展示字段立刻生效。
            // 别只搬 APY——Edit 弹层现在也能改名字。
            scheduled.name = product.name
            scheduled.note = product.note
            scheduled.structuredParameters = product.structuredParameters
            try scheduled.validate()
            candidate.earnProducts[index] = scheduled
            try await ledgerRepository.save(candidate, for: scope)
            snapshot = candidate
            recalculateSummary()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func subscribe(product: EarnProduct, quantity: Double, note: String? = nil) async -> Bool {
        guard let productIndex = snapshot.earnProducts.firstIndex(where: { $0.id == product.id }) else {
            errorMessage = LedgerViewModelError.unknownProduct.localizedDescription
            return false
        }

        do {
            var candidate = snapshot
            var storedProduct = candidate.earnProducts[productIndex]
            let correctedAsset = correctedAssetIfSafe(for: storedProduct)
            if correctedAsset != storedProduct.asset {
                storedProduct.asset = correctedAsset
                try storedProduct.validate()
                candidate.earnProducts[productIndex] = storedProduct
            }
            candidate.entries.append(try LedgerEntry.earnSubscribe(
                product: storedProduct,
                quantity: quantity,
                occurredAt: Date(),
                note: note
            ))
            let nextProjection = try LedgerProjection(entries: candidate.entries)
            try await ledgerRepository.save(candidate, for: scope)
            snapshot = candidate
            projection = nextProjection
            recalculateSummary()
            await refreshValuation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 下架产品。把 Earn 账户的完整余额退回产品推导出的来源账户，
    /// 并在同一次原子保存里给产品打下架标记——记录保留，
    /// 因为历史流水还要靠它显示当时的产品名和 APY，删掉会让流水变成孤儿。
    /// 已计提的利息不受影响：它们是独立的 interest 流水，这里一条都不碰。
    func delist(product: EarnProduct) async -> Bool {
        guard product.canDelist else {
            errorMessage = LedgerViewModelError.unknownProduct.localizedDescription
            return false
        }
        guard let index = snapshot.earnProducts.firstIndex(where: { $0.id == product.id }),
              snapshot.earnProducts[index].canDelist else {
            errorMessage = LedgerViewModelError.unknownProduct.localizedDescription
            return false
        }

        do {
            let storedProduct = snapshot.earnProducts[index]
            let delistedAt = Date()
            let holding = projection.balance(
                in: .earn(productID: storedProduct.id),
                asset: storedProduct.asset
            )
            var candidate = snapshot
            if holding > LedgerEntry.balanceTolerance {
                candidate.entries.append(
                    try LedgerEntry.earnRedeem(
                        product: storedProduct,
                        quantity: holding,
                        occurredAt: delistedAt,
                        note: "Delisted"
                    )
                )
            }
            candidate.earnProducts[index].delistedAt = delistedAt
            let nextProjection = try LedgerProjection(entries: candidate.entries)
            try await ledgerRepository.save(candidate, for: scope)
            snapshot = candidate
            projection = nextProjection
            recalculateSummary()
            await refreshValuation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func redeem(product: EarnProduct, quantity: Double, note: String? = nil) async -> Bool {
        guard snapshot.earnProducts.contains(where: { $0.id == product.id }) else {
            errorMessage = LedgerViewModelError.unknownProduct.localizedDescription
            return false
        }
        return await append {
            try LedgerEntry.earnRedeem(
                product: product,
                quantity: quantity,
                occurredAt: Date(),
                note: note
            )
        }
    }

    /// Records a payout only when the provider actually pays it. Compound
    /// products credit the Earn principal; simple-interest products credit the
    /// product's funding account, as defined by `LedgerEntry.interestPayout`.
    func recordInterestPayout(
        product: EarnProduct,
        quantity: Double,
        occurredAt: Date = Date()
    ) async -> Bool {
        guard snapshot.earnProducts.contains(where: { $0.id == product.id }) else {
            errorMessage = LedgerViewModelError.unknownProduct.localizedDescription
            return false
        }
        guard projection.balance(in: .earn(productID: product.id), asset: product.asset) > LedgerEntry.balanceTolerance else {
            errorMessage = LedgerViewModelError.noEarnHolding.localizedDescription
            return false
        }
        guard isInterestPayoutDue(for: product, asOf: occurredAt) else {
            errorMessage = LedgerViewModelError.interestPayoutNotDue.localizedDescription
            return false
        }
        return await append {
            try LedgerEntry.interestPayout(
                product: product,
                quantity: quantity,
                occurredAt: occurredAt
            )
        }
    }

    func nextPayoutDate(for product: EarnProduct, asOf date: Date = Date()) -> Date? {
        EarnInterestCalculator.nextPayoutDate(
            product: product,
            entries: snapshot.entries,
            asOf: date
        )
    }

    func isInterestPayoutDue(for product: EarnProduct, asOf date: Date = Date()) -> Bool {
        guard let next = nextPayoutDate(for: product, asOf: date) else { return false }
        return date >= next
    }

    func reverse(_ entry: LedgerEntry) async -> Bool {
        guard canReverse(entry) else {
            errorMessage = LedgerViewModelError.cannotReverse.localizedDescription
            return false
        }
        return await append {
            try LedgerEntry.reversal(of: entry, occurredAt: Date(), note: "Reversal")
        }
    }

    func canReverse(_ entry: LedgerEntry) -> Bool {
        entry.kind != .openingBalance
            && entry.kind != .reversal
            && !snapshot.entries.contains(where: { $0.reversesEntryID == entry.id })
    }

    private func append(_ makeEntry: () throws -> LedgerEntry) async -> Bool {
        do {
            let entry = try makeEntry()
            var candidate = snapshot
            candidate.entries.append(entry)
            let nextProjection = try LedgerProjection(entries: candidate.entries)
            try await ledgerRepository.save(candidate, for: scope)
            snapshot = candidate
            projection = nextProjection
            recalculateSummary()
            await refreshValuation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func correctedAssetIfSafe(for product: EarnProduct) -> LedgerAsset {
        // Once any product entry exists, changing its asset would split historical postings
        // across two balance keys. The USDG regression happened before a subscription could
        // succeed, so correcting untouched products is both sufficient and migration-safe.
        guard !snapshot.entries.contains(where: { $0.earnProductID == product.id }) else {
            return product.asset
        }
        return preferredEarnAsset(code: product.asset.code, fallbackKind: product.asset.kind)
    }

    private func positiveAssets(
        code: String,
        in account: LedgerAccountReference
    ) -> [LedgerAsset] {
        projection.balances
            .filter { key, quantity in
                key.account == account
                    && key.asset.code == code
                    && key.asset.canEnterEarn
                    && quantity > LedgerEntry.balanceTolerance
            }
            .map(\.key.asset)
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private func fundingAccount(for asset: LedgerAsset) -> LedgerAccountReference {
        asset.kind == .cryptocurrency ? .trading : .fiat("exchange")
    }

    private func refreshValuation() async {
        let symbols = LedgerValuation.requiredQuoteSymbols(for: projection)
        if let quoteRepository {
            let refresh = await quoteRepository.refreshQuotes(for: symbols)
            refresh.quotes.forEach { quotes[$0.key] = $0.value }
            // A permanently unsupported or delisted symbol fails on every pull-to-refresh.
            // Its missing value is already represented by `—` in the affected row and totals;
            // repeating a page-level banner adds no recovery path and makes refresh feel broken.
            if refresh.usedCachedValues {
                valuationStatusMessage = "Some market prices are from the last available update."
            } else {
                valuationStatusMessage = nil
            }
            // 持仓变了订阅集合就得跟着变。start 对已订过的标的是幂等的，
            // 所以这里每轮都调没有额外代价。
            await startStreamingIfNeeded(symbols: symbols)
        }
        if let exchangeRateClient {
            do {
                let latest = try await exchangeRateClient.latestRates()
                exchangeRates = latest
                preferences?.save(snapshot: latest)
            } catch {
                if exchangeRates == nil {
                    valuationStatusMessage = "Exchange rates are unavailable. Pull to refresh and try again."
                }
            }
        }
        recalculateSummary()
    }

    /// 把加密的实时推送接上。
    ///
    /// 美股不走这条路 —— Binance Stocks 没有公开行情流，它们由 `refreshValuation`
    /// 按轮询更新（一次请求覆盖所有标的）。`MarketStreamClient` 自己会忽略非加密
    /// 的代号，所以这里直接把整个集合交过去。
    private func startStreamingIfNeeded(symbols: Set<String>) async {
        guard let streamClient, !symbols.isEmpty else { return }
        // 订阅是幂等的，每轮估值刷新都调一次，持仓增删就自动跟上。
        await streamClient.subscribe(symbols: symbols)
        // 接收循环只开一次。再开一次会把上一条流结束掉，表现是价格突然不动了。
        guard streamTask == nil else { return }
        let stream = await streamClient.ticks()
        streamTask = Task { [weak self] in
            for await tick in stream {
                await self?.apply(tick)
            }
        }
    }

    /// 把一条 tick 合并进已有报价。
    ///
    /// 涨跌幅要重算，但**不能**用推送去猜基准：上一次完整报价里的
    /// `price` 和 `changePercent` 已经隐含了「北京时间今日」的基准价
    /// （base = price / (1 + change/100)），用它算出来的新涨跌和 Worker
    /// 那边完全一致 —— 既不用多打一次请求，也不会两边算出两个数。
    private func apply(_ tick: MarketStreamTick) {
        guard let existing = quotes[tick.symbol] ?? quotes["\(tick.symbol)-USD"] else { return }
        let key = quotes[tick.symbol] != nil ? tick.symbol : "\(tick.symbol)-USD"
        let ratio = 1 + existing.changePercent / 100
        let base = ratio > 0 ? existing.price / ratio : 0
        let change = base > 0 ? (tick.priceUSD - base) / base * 100 : existing.changePercent

        quotes[key] = MarketQuote(
            symbol: existing.symbol,
            currency: existing.currency,
            price: tick.priceUSD,
            changePercent: change,
            series: existing.series,
            marketTimeMilliseconds: existing.marketTimeMilliseconds,
            fetchedAtMilliseconds: tick.receivedAtMilliseconds
        )
        recalculateSummary()
    }

    /// 页面消失 / App 进后台时调用。后台留着连接既费电，回来时它多半也已经死了。
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        let client = streamClient
        Task { await client?.stop() }
    }

    deinit {
        streamTask?.cancel()
    }

    func selectHistoryRange(_ range: PortfolioHistoryRange) {
        guard historyRange != range else { return }
        historyRange = range
        portfolioPreferences?.save(historyRange: range)
        rebuildChartSeries()
    }

    private func recalculateSummary() {
        portfolioSummary = LedgerValuation.summary(
            entries: snapshot.entries,
            projection: projection,
            quotes: quotes,
            exchangeRates: exchangeRates
        )
        rebuildChartSeries()
    }

    private func rebuildChartSeries() {
        var series = LedgerValuation.series(
            entries: snapshot.entries,
            quotes: quotes,
            exchangeRates: exchangeRates,
            range: historyRange
        )
        // 行情序列可能比头条价慢一拍。图的末点必须落在上面那个总额上，
        // 否则同一屏里两个数对不上（`summary` 里也是这么钉的）。
        if let total = portfolioSummary.totalValueUSD, let last = series.last {
            series[series.count - 1] = PortfolioHistoryPoint(
                timestampMilliseconds: last.timestampMilliseconds,
                value: total
            )
        }
        chartSeries = series
    }
}

enum LedgerViewModelError: LocalizedError {
    case duplicateProduct
    case unknownProduct
    case noEarnHolding
    case interestPayoutNotDue
    case cannotReverse

    var errorDescription: String? {
        switch self {
        case .duplicateProduct: "This Earn product already exists."
        case .unknownProduct: "This Earn product no longer exists."
        case .noEarnHolding: "Subscribe before recording an interest payout."
        case .interestPayoutNotDue: "A full payout cycle has not elapsed yet."
        case .cannotReverse: "This transaction cannot be reversed."
        }
    }
}
