import Combine
import Foundation

@MainActor
final class ExchangeRateViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready(isCached: Bool)
        case failed(message: String)
    }

    struct Conversion: Identifiable, Equatable {
        let currency: CurrencyCode
        let amount: Double
        let unitRate: Double

        var id: CurrencyCode { currency }
    }

    @Published var amountText = "1,000"
    @Published var baseCurrency = CurrencyCode.cny
    @Published private(set) var snapshot: ExchangeRateSnapshot?
    @Published private(set) var loadState = LoadState.idle

    private let client: any ExchangeRateServing
    private let defaults: UserDefaults
    private let cacheKey = "pawfolio.exchange-rate.snapshot.v1"

    init(
        client: any ExchangeRateServing = LiveExchangeRateClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
    }

    var amount: Double {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Double(normalized) ?? 0
        return value.isFinite ? max(0, value) : 0
    }

    var conversions: [Conversion] {
        guard let snapshot else { return [] }
        return CurrencyCode.allCases.compactMap { currency in
            guard currency != baseCurrency,
                  let converted = snapshot.converted(amount, from: baseCurrency, to: currency),
                  let unitRate = snapshot.converted(1, from: baseCurrency, to: currency) else {
                return nil
            }
            return Conversion(currency: currency, amount: converted, unitRate: unitRate)
        }
    }

    var updatedAt: Date? {
        snapshot?.fetchedAt
    }

    func loadIfNeeded() async {
        guard loadState == .idle else { return }

        if let cached = loadCache() {
            snapshot = cached
            loadState = .ready(isCached: true)
        }

        await refresh()
    }

    func refresh() async {
        if snapshot == nil {
            loadState = .loading
        }

        do {
            let latest = try await client.latestRates()
            snapshot = latest
            saveCache(latest)
            loadState = .ready(isCached: false)
        } catch {
            if snapshot != nil {
                loadState = .ready(isCached: true)
            } else {
                loadState = .failed(message: (error as? LocalizedError)?.errorDescription ?? "暂时无法获取最新汇率。")
            }
        }
    }

    func chooseBase(_ currency: CurrencyCode) {
        baseCurrency = currency
    }

    func formatInput() {
        guard !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        amountText = amount.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
    }

    private func loadCache() -> ExchangeRateSnapshot? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data)
    }

    private func saveCache(_ snapshot: ExchangeRateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}

