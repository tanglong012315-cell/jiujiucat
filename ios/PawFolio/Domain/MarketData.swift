import Foundation

struct AssetSearchResult: Codable, Equatable, Identifiable, Sendable {
    let symbol: String
    let quoteSymbol: String
    let name: String
    let assetType: AssetType
    let exchange: String

    var id: String { quoteSymbol }

    static let offlineFallbacks: [Self] = [
        Self(symbol: "AAPL", quoteSymbol: "AAPL", name: "Apple Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "MSFT", quoteSymbol: "MSFT", name: "Microsoft Corporation", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "NVDA", quoteSymbol: "NVDA", name: "NVIDIA Corporation", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "AMZN", quoteSymbol: "AMZN", name: "Amazon.com, Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "GOOGL", quoteSymbol: "GOOGL", name: "Alphabet Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "META", quoteSymbol: "META", name: "Meta Platforms, Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "TSLA", quoteSymbol: "TSLA", name: "Tesla, Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "MSTR", quoteSymbol: "MSTR", name: "Strategy Inc.", assetType: .equity, exchange: "NASDAQ"),
        Self(symbol: "QQQ", quoteSymbol: "QQQ", name: "Invesco QQQ Trust", assetType: .etf, exchange: "NASDAQ"),
        Self(symbol: "SPY", quoteSymbol: "SPY", name: "SPDR S&P 500 ETF Trust", assetType: .etf, exchange: "NYSEArca"),
        Self(symbol: "VOO", quoteSymbol: "VOO", name: "Vanguard S&P 500 ETF", assetType: .etf, exchange: "NYSEArca"),
        Self(symbol: "BTC", quoteSymbol: "BTC-USD", name: "Bitcoin USD", assetType: .cryptocurrency, exchange: "CCC"),
        Self(symbol: "ETH", quoteSymbol: "ETH-USD", name: "Ethereum USD", assetType: .cryptocurrency, exchange: "CCC"),
        Self(symbol: "SOL", quoteSymbol: "SOL-USD", name: "Solana USD", assetType: .cryptocurrency, exchange: "CCC"),
        Self(symbol: "BNB", quoteSymbol: "BNB-USD", name: "BNB USD", assetType: .cryptocurrency, exchange: "CCC"),
        Self(symbol: "XRP", quoteSymbol: "XRP-USD", name: "XRP USD", assetType: .cryptocurrency, exchange: "CCC"),
        Self(symbol: "DOGE", quoteSymbol: "DOGE-USD", name: "Dogecoin USD", assetType: .cryptocurrency, exchange: "CCC")
    ]

    static func offlineMatches(for query: String) -> [Self] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        return offlineFallbacks
            .filter {
                "\($0.symbol) \($0.quoteSymbol) \($0.name)"
                    .lowercased()
                    .contains(needle)
            }
            .sorted { lhs, rhs in
                let lhsExact = [lhs.symbol, lhs.quoteSymbol].contains { $0.lowercased() == needle }
                let rhsExact = [rhs.symbol, rhs.quoteSymbol].contains { $0.lowercased() == needle }
                if lhsExact != rhsExact { return lhsExact }
                return lhs.symbol < rhs.symbol
            }
            .prefix(12)
            .map { $0 }
    }
}

struct MarketPricePoint: Codable, Equatable, Sendable {
    let timestampMilliseconds: TimeInterval
    let price: Double
}

struct MarketQuote: Codable, Equatable, Identifiable, Sendable {
    let symbol: String
    let currency: String
    let price: Double
    let changePercent: Double
    let series: [MarketPricePoint]
    let marketTimeMilliseconds: TimeInterval?
    let fetchedAtMilliseconds: TimeInterval

    var id: String { symbol }
}

struct MarketPriceHistory: Codable, Equatable, Identifiable, Sendable {
    let symbol: String
    let currency: String
    let series: [MarketPricePoint]
    let fetchedAtMilliseconds: TimeInterval

    var id: String { symbol }
}

struct MarketQuoteRefresh: Equatable, Sendable {
    let quotes: [String: MarketQuote]
    let failedSymbols: Set<String>
    let usedCachedValues: Bool
}

struct MarketHistoryRefresh: Equatable, Sendable {
    let histories: [String: MarketPriceHistory]
    let failedSymbols: Set<String>
    let usedCachedValues: Bool
}
