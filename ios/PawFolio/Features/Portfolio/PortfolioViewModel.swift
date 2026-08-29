import Combine
import Foundation

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published private(set) var holdings: [Holding] = []
    @Published private(set) var quotes: [String: MarketQuote] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingQuotes = false
    @Published private(set) var quoteStatusMessage: String?
    @Published private(set) var historyRange: PortfolioHistoryRange
    @Published private(set) var portfolioHistory: PortfolioHistoryResult?
    @Published private(set) var isLoadingHistory = false
    @Published var errorMessage: String?

    private let repository: any HoldingRepository
    private let quoteRepository: any MarketQuoteRepositoryServing
    private var shortHistories: [String: MarketPriceHistory] = [:]
    private var oneYearHistories: [String: MarketPriceHistory] = [:]
    private var failedOneYearHistorySymbols: Set<String> = []
    private var hasLoaded = false

    init(
        repository: any HoldingRepository = LocalHoldingRepository(),
        quoteRepository: any MarketQuoteRepositoryServing = CachedMarketQuoteRepository()
    ) {
        self.repository = repository
        self.quoteRepository = quoteRepository
        historyRange = UserDefaults.standard.string(forKey: "portfolio.historyRange")
            .flatMap(PortfolioHistoryRange.init(rawValue:)) ?? .week
    }

    var openHoldings: [Holding] {
        holdings
            .filter { !$0.isDeleted && !$0.isClosed }
            .sorted { lhs, rhs in
                let lhsTime = lhs.updatedAt ?? lhs.createdAt
                let rhsTime = rhs.updatedAt ?? rhs.createdAt
                return lhsTime > rhsTime
            }
    }

    var totalCostBasis: Double {
        openHoldings.reduce(0) { $0 + $1.currentCostBasis }
    }

    var totalValue: Double? {
        let now = Date().timeIntervalSince1970 * 1_000
        guard !openHoldings.isEmpty else { return 0 }

        var total = 0.0
        for holding in openHoldings {
            let metrics = metrics(for: holding, at: now)
            guard let value = metrics.value else { return nil }
            total += value
        }
        return total
    }

    var totalProfit: Double? {
        let now = Date().timeIntervalSince1970 * 1_000
        guard !openHoldings.isEmpty else { return 0 }

        var total = 0.0
        for holding in openHoldings {
            let metrics = metrics(for: holding, at: now)
            guard let profit = metrics.profit else { return nil }
            total += profit
        }
        return total
    }

    var totalProfitPercent: Double? {
        guard let totalProfit, totalCostBasis > 0 else { return nil }
        return totalProfit / totalCostBasis * 100
    }

    var accruedInterest: Double {
        let now = Date().timeIntervalSince1970 * 1_000
        return openHoldings.reduce(0) { total, holding in
            total + HoldingValuation.accruedInterest(for: holding, at: now)
        }
    }

    var interestPrincipal: Double {
        openHoldings
            .filter { $0.isInterestBearing }
            .reduce(0) { $0 + $1.currentCostBasis }
    }

    var marketCostBasis: Double {
        totalCostBasis - interestPrincipal
    }

    var hasMarketHoldings: Bool {
        openHoldings.contains { $0.holdingKind != .interest }
    }

    var historyStatusMessage: String? {
        if portfolioHistory != nil {
            if historyRange.prefersOneYearHistory,
               !failedOneYearHistorySymbols.isEmpty {
                return "部分标的一年日线暂不可用，已用较短行情补齐。"
            }
            return nil
        }
        guard !openHoldings.isEmpty else { return nil }
        if openHoldings.contains(where: {
            $0.holdingKind != .interest && currentMarketPrices[$0.quoteSymbol.uppercased()] == nil
        }) {
            return "部分美元行情尚不可用，暂时无法生成总资产走势。"
        }
        return "还没有足够的历史变化来绘制走势。"
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storedHoldings = try await repository.load()
            holdings = HoldingPositionAdjustment.retainedClosedHistory(
                from: storedHoldings,
                at: Date().timeIntervalSince1970 * 1_000
            )
            await loadCachedShortHistories()
            await refreshQuotes()
            if historyRange.prefersOneYearHistory {
                await refreshOneYearHistories()
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func upsert(_ holding: Holding) async -> Bool {
        var candidate = holdings
        var saved = holding
        saved.schemaVersion = Holding.currentSchemaVersion
        saved.updatedAt = Date().timeIntervalSince1970 * 1_000

        if let index = candidate.firstIndex(where: { $0.id == saved.id }) {
            candidate[index] = saved
        } else {
            candidate.append(saved)
        }

        let didSave = await persist(candidate)
        if didSave, saved.holdingKind != .interest {
            Task {
                await refreshQuotes()
                if historyRange.prefersOneYearHistory {
                    await refreshOneYearHistories()
                }
            }
        }
        return didSave
    }

    func adjust(_ request: HoldingAdjustmentRequest) async throws {
        let candidate = try HoldingPositionAdjustment.applying(request, to: holdings)
        try await persistThrowing(candidate)
    }

    func holding(withID id: String) -> Holding? {
        holdings.first { $0.id == id && !$0.isDeleted }
    }

    func skipInterestSettlement(holdingID: String, date: String) async throws {
        let candidate = try HoldingRecordMutation.skippingInterestSettlement(
            holdingID: holdingID,
            date: date,
            occurredAt: Date().timeIntervalSince1970 * 1_000,
            in: holdings
        )
        try await persistThrowing(candidate)
    }

    func restoreInterestSettlement(holdingID: String, date: String) async throws {
        let candidate = try HoldingRecordMutation.restoringInterestSettlement(
            holdingID: holdingID,
            date: date,
            occurredAt: Date().timeIntervalSince1970 * 1_000,
            in: holdings
        )
        try await persistThrowing(candidate)
    }

    func upsertDividendRecord(_ request: DividendRecordRequest) async throws {
        let candidate = try HoldingRecordMutation.upsertingDividendRecord(request, in: holdings)
        try await persistThrowing(candidate)
    }

    func deleteDividendRecord(holdingID: String, recordID: String) async throws {
        let candidate = try HoldingRecordMutation.deletingDividendRecord(
            holdingID: holdingID,
            recordID: recordID,
            occurredAt: Date().timeIntervalSince1970 * 1_000,
            in: holdings
        )
        try await persistThrowing(candidate)
    }

    func delete(_ holding: Holding) async {
        guard let index = holdings.firstIndex(where: { $0.id == holding.id }) else { return }

        var candidate = holdings
        let now = Date().timeIntervalSince1970 * 1_000
        candidate[index].schemaVersion = Holding.currentSchemaVersion
        candidate[index].deletedAt = now
        candidate[index].updatedAt = now
        _ = await persist(candidate)
    }

    private func persist(_ candidate: [Holding]) async -> Bool {
        do {
            try await repository.save(candidate)
            holdings = candidate
            rebuildPortfolioHistory()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private func persistThrowing(_ candidate: [Holding]) async throws {
        do {
            try await repository.save(candidate)
            holdings = candidate
            rebuildPortfolioHistory()
        } catch {
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    func metrics(for holding: Holding, at timestampMilliseconds: TimeInterval? = nil) -> HoldingMetrics {
        return HoldingValuation.metrics(
            for: holding,
            marketPrice: marketPrice(for: holding),
            at: timestampMilliseconds ?? Date().timeIntervalSince1970 * 1_000
        )
    }

    func marketPrice(for holding: Holding) -> Double? {
        let quote = quotes[holding.quoteSymbol.uppercased()]
        return quote?.currency.uppercased() == "USD" ? quote?.price : nil
    }

    func refreshQuotes() async {
        let symbols = Set(
            openHoldings
                .filter { $0.holdingKind != .interest }
                .map { $0.quoteSymbol.uppercased() }
        )
        guard !symbols.isEmpty else {
            quotes = [:]
            quoteStatusMessage = nil
            rebuildPortfolioHistory()
            return
        }

        isRefreshingQuotes = true
        defer { isRefreshingQuotes = false }

        let cached = await quoteRepository.cachedQuotes(for: symbols)
        if !cached.isEmpty {
            quotes.merge(cached) { _, cachedValue in cachedValue }
            mergeShortHistories(from: cached)
            quoteStatusMessage = "正在使用最近一次行情"
            rebuildPortfolioHistory()
        }

        let result = await quoteRepository.refreshQuotes(for: symbols)
        quotes = result.quotes
        mergeShortHistories(from: result.quotes)
        rebuildPortfolioHistory()

        let unsupportedCurrencyCount = result.quotes.values.filter {
            $0.currency.uppercased() != "USD"
        }.count

        if !result.failedSymbols.isEmpty {
            quoteStatusMessage = "\(result.failedSymbols.count) 个标的暂时无法获取行情"
        } else if unsupportedCurrencyCount > 0 {
            quoteStatusMessage = "\(unsupportedCurrencyCount) 个非美元标的暂未计入总资产"
        } else {
            quoteStatusMessage = result.usedCachedValues ? "部分行情来自本地缓存" : "行情已更新"
        }
    }

    func selectHistoryRange(_ range: PortfolioHistoryRange) async {
        guard historyRange != range else { return }
        historyRange = range
        UserDefaults.standard.set(range.rawValue, forKey: "portfolio.historyRange")
        rebuildPortfolioHistory()

        if range.prefersOneYearHistory {
            await refreshOneYearHistories()
        }
    }

    private var historyMarketSymbols: Set<String> {
        Set(
            holdings
                .filter { !$0.isDeleted && $0.holdingKind != .interest }
                .map { $0.quoteSymbol.uppercased() }
        )
    }

    private var currentMarketPrices: [String: Double] {
        quotes.reduce(into: [:]) { prices, entry in
            guard entry.value.currency.uppercased() == "USD",
                  entry.value.price.isFinite,
                  entry.value.price > 0 else {
                return
            }
            prices[entry.key.uppercased()] = entry.value.price
        }
    }

    private func loadCachedShortHistories() async {
        let cached = await quoteRepository.cachedQuotes(for: historyMarketSymbols)
        mergeShortHistories(from: cached)
        rebuildPortfolioHistory()
    }

    private func mergeShortHistories(from quotes: [String: MarketQuote]) {
        for (symbol, quote) in quotes where !quote.series.isEmpty {
            shortHistories[symbol.uppercased()] = MarketPriceHistory(
                symbol: quote.symbol,
                currency: quote.currency,
                series: quote.series,
                fetchedAtMilliseconds: quote.fetchedAtMilliseconds
            )
        }
    }

    private func refreshOneYearHistories() async {
        let symbols = historyMarketSymbols
        guard !symbols.isEmpty else {
            oneYearHistories = [:]
            failedOneYearHistorySymbols = []
            rebuildPortfolioHistory()
            return
        }

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let cached = await quoteRepository.cachedOneYearHistories(for: symbols)
        for symbol in symbols {
            oneYearHistories[symbol] = cached[symbol]
        }
        rebuildPortfolioHistory()

        let result = await quoteRepository.refreshOneYearHistories(for: symbols)
        for symbol in symbols {
            oneYearHistories[symbol] = result.histories[symbol]
        }
        failedOneYearHistorySymbols = result.failedSymbols
        rebuildPortfolioHistory()
    }

    private func rebuildPortfolioHistory() {
        portfolioHistory = PortfolioHistoryBuilder.build(
            holdings: holdings,
            currentPrices: currentMarketPrices,
            shortHistories: shortHistories,
            oneYearHistories: oneYearHistories,
            range: historyRange,
            endingAt: Date().timeIntervalSince1970 * 1_000
        )
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "本地持仓保存失败，请重试。"
    }

    // MARK: 快捷添加
    //
    // 对应 Web 的 `RECOMMENDED_ASSETS` 与 `#portfolio-recommend`。整块可以关掉，
    // 关掉的选择记在本地（Web 用 `PORTFOLIO_RECOMMEND_DISMISSED_KEY`）。

    static let recommendedAssets: [AssetSearchResult] = [
        AssetSearchResult(
            symbol: "VOO", quoteSymbol: "VOO", name: "Vanguard S&P 500 ETF",
            assetType: .etf, exchange: "NYSEArca"
        ),
        AssetSearchResult(
            symbol: "AAPL", quoteSymbol: "AAPL", name: "Apple Inc.",
            assetType: .equity, exchange: "NASDAQ"
        ),
        AssetSearchResult(
            symbol: "BTC", quoteSymbol: "BTC-USD", name: "Bitcoin",
            assetType: .cryptocurrency, exchange: "CCC"
        )
    ]

    private static let recommendDismissedKey = "pawfolio.portfolio.recommend-dismissed"

    @Published private(set) var recommendQuotes: [String: MarketQuote] = [:]
    @Published var isRecommendDismissed = UserDefaults.standard.bool(
        forKey: PortfolioViewModel.recommendDismissedKey
    ) {
        didSet {
            UserDefaults.standard.set(isRecommendDismissed, forKey: Self.recommendDismissedKey)
        }
    }

    func recommendQuote(for asset: AssetSearchResult) -> MarketQuote? {
        // 已持有该标的时，复用持仓那边已经取到的报价，避免重复请求。
        quotes[asset.quoteSymbol] ?? recommendQuotes[asset.quoteSymbol]
    }

    func loadRecommendQuotes() async {
        guard !isRecommendDismissed else { return }

        let symbols = Set(Self.recommendedAssets.map(\.quoteSymbol))
        let cached = await quoteRepository.cachedQuotes(for: symbols)
        if !cached.isEmpty {
            recommendQuotes = cached
        }

        let refreshed = await quoteRepository.refreshQuotes(for: symbols)
        if !refreshed.quotes.isEmpty {
            recommendQuotes = refreshed.quotes
        }
    }
}
