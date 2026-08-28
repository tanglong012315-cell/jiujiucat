import Foundation

protocol MarketQuoteRepositoryServing: Sendable {
    func cachedQuotes(for symbols: Set<String>) async -> [String: MarketQuote]
    func refreshQuotes(for symbols: Set<String>) async -> MarketQuoteRefresh
    func cachedOneYearHistories(for symbols: Set<String>) async -> [String: MarketPriceHistory]
    func refreshOneYearHistories(for symbols: Set<String>) async -> MarketHistoryRefresh
}

actor CachedMarketQuoteRepository: MarketQuoteRepositoryServing {
    private struct CacheEnvelope: Codable {
        static let currentVersion = 1

        let version: Int
        let quotes: [String: MarketQuote]
    }

    private struct HistoryCacheEnvelope: Codable {
        static let currentVersion = 1

        let version: Int
        let histories: [String: MarketPriceHistory]
    }

    private let client: any MarketDataServing
    private let fileURL: URL
    private let historyFileURL: URL
    private let cacheLifetimeMilliseconds: TimeInterval

    init(
        client: any MarketDataServing = LiveMarketDataClient(),
        fileURL: URL? = nil,
        historyFileURL: URL? = nil,
        cacheLifetime: TimeInterval = 12 * 60 * 60
    ) {
        self.client = client
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.historyFileURL = historyFileURL
            ?? Self.defaultHistoryFileURL(quoteFileURL: fileURL)
        cacheLifetimeMilliseconds = cacheLifetime * 1_000
    }

    func cachedQuotes(for symbols: Set<String>) async -> [String: MarketQuote] {
        let allQuotes = loadCache()
        return allQuotes.filter { symbols.contains($0.key) }
    }

    func refreshQuotes(for symbols: Set<String>) async -> MarketQuoteRefresh {
        let normalizedSymbols = Set(symbols.map { $0.uppercased() })
        guard !normalizedSymbols.isEmpty else {
            return MarketQuoteRefresh(quotes: [:], failedSymbols: [], usedCachedValues: false)
        }

        let cached = loadCache()
        var fetched: [String: MarketQuote] = [:]
        var failed: Set<String> = []

        await withTaskGroup(of: (String, MarketQuote?).self) { group in
            for symbol in normalizedSymbols {
                group.addTask { [client] in
                    do {
                        return (symbol, try await client.quote(symbol: symbol))
                    } catch {
                        return (symbol, nil)
                    }
                }
            }

            for await (symbol, quote) in group {
                if let quote {
                    fetched[symbol] = quote
                } else {
                    failed.insert(symbol)
                }
            }
        }

        if !fetched.isEmpty {
            var updatedCache = cached
            fetched.forEach { updatedCache[$0.key] = $0.value }
            try? saveCache(updatedCache)
        }

        let now = Date().timeIntervalSince1970 * 1_000
        var resolved = fetched
        var usedCachedValues = false
        for symbol in failed {
            guard let cachedQuote = cached[symbol],
                  now - cachedQuote.fetchedAtMilliseconds <= cacheLifetimeMilliseconds else {
                continue
            }
            resolved[symbol] = cachedQuote
            usedCachedValues = true
        }

        return MarketQuoteRefresh(
            quotes: resolved,
            failedSymbols: failed.subtracting(resolved.keys),
            usedCachedValues: usedCachedValues
        )
    }

    func cachedOneYearHistories(
        for symbols: Set<String>
    ) async -> [String: MarketPriceHistory] {
        let now = Date().timeIntervalSince1970 * 1_000
        return loadHistoryCache().filter {
            symbols.contains($0.key)
                && now - $0.value.fetchedAtMilliseconds <= cacheLifetimeMilliseconds
        }
    }

    func refreshOneYearHistories(for symbols: Set<String>) async -> MarketHistoryRefresh {
        let normalizedSymbols = Set(symbols.map { $0.uppercased() })
        guard !normalizedSymbols.isEmpty else {
            return MarketHistoryRefresh(histories: [:], failedSymbols: [], usedCachedValues: false)
        }

        let now = Date().timeIntervalSince1970 * 1_000
        let cache = loadHistoryCache()
        let freshCache = cache.filter {
            normalizedSymbols.contains($0.key)
                && now - $0.value.fetchedAtMilliseconds <= cacheLifetimeMilliseconds
        }
        let targets = normalizedSymbols.subtracting(freshCache.keys)
        var fetched: [String: MarketPriceHistory] = [:]
        var failed: Set<String> = []

        await withTaskGroup(of: (String, MarketPriceHistory?).self) { group in
            for symbol in targets {
                group.addTask { [client] in
                    do {
                        return (symbol, try await client.oneYearHistory(symbol: symbol))
                    } catch {
                        return (symbol, nil)
                    }
                }
            }

            for await (symbol, history) in group {
                if let history {
                    fetched[symbol] = history
                } else {
                    failed.insert(symbol)
                }
            }
        }

        if !fetched.isEmpty {
            var updatedCache = cache
            fetched.forEach { updatedCache[$0.key] = $0.value }
            try? saveHistoryCache(updatedCache)
        }

        var resolved = freshCache
        fetched.forEach { resolved[$0.key] = $0.value }
        return MarketHistoryRefresh(
            histories: resolved,
            failedSymbols: failed,
            usedCachedValues: !freshCache.isEmpty
        )
    }

    private func loadCache() -> [String: MarketQuote] {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.version == CacheEnvelope.currentVersion else {
            return [:]
        }
        return envelope.quotes
    }

    private func saveCache(_ quotes: [String: MarketQuote]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope = CacheEnvelope(version: CacheEnvelope.currentVersion, quotes: quotes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: fileURL, options: [.atomic])
    }

    private func loadHistoryCache() -> [String: MarketPriceHistory] {
        guard let data = try? Data(contentsOf: historyFileURL),
              let envelope = try? JSONDecoder().decode(HistoryCacheEnvelope.self, from: data),
              envelope.version == HistoryCacheEnvelope.currentVersion else {
            return [:]
        }
        return envelope.histories
    }

    private func saveHistoryCache(_ histories: [String: MarketPriceHistory]) throws {
        try FileManager.default.createDirectory(
            at: historyFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope = HistoryCacheEnvelope(
            version: HistoryCacheEnvelope.currentVersion,
            histories: histories
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: historyFileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PawFolio", isDirectory: true)
            .appendingPathComponent("market-quotes-v1.json", isDirectory: false)
    }

    private static func defaultHistoryFileURL(quoteFileURL: URL?) -> URL {
        let directory = quoteFileURL?.deletingLastPathComponent()
            ?? defaultFileURL().deletingLastPathComponent()
        return directory.appendingPathComponent("market-history-1y-v1.json", isDirectory: false)
    }
}
