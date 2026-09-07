import Foundation
import os

/// 并发拉取的单个结果。
///
/// 这两个类型存在的唯一原因是**绕开一个编译器 bug**：`withTaskGroup(of:)` 的子任务
/// 结果类型如果是元组（这里原本是 `(String, MarketQuote?)`），**开了优化的构建会在
/// 任务组收结果时崩溃** —— `swift::AsyncTask::completeFuture` 里 `__cxa_pure_virtual`，
/// SIGABRT，崩溃报告里一帧应用代码都没有。
///
/// 2026-09-02 在 Xcode 17F113 / iOS 26.5.2 上量到：同一份代码只改结果类型，
/// 元组版模拟器上 10 次崩 8 次，换成下面这种具名结构体 10 次一次都不崩。
/// `-Onone` 不会崩，`-O` 和 `-Osize` 都会，真机和模拟器都能复现。
///
/// **所以：这个仓库里的 `withTaskGroup` 一律不要用元组做结果类型。**
struct MarketQuoteFetchResult: Sendable {
    let symbol: String
    let quote: MarketQuote?
}

/// 同上，一年日线的并发结果。见 `MarketQuoteFetchResult` 的说明。
struct MarketHistoryFetchResult: Sendable {
    let symbol: String
    let history: MarketPriceHistory?
}

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

    /// 缓存写盘失败的次数。**不为零就说明本地缓存已经形同虚设**：磁盘满、数据保护
    /// 未解锁、或者路径被占，都会让写入一直失败，表现是每次启动都要重新联网、离线时
    /// 一片空白。原来这里是 `try?`，出了这种事完全查不到。
    private(set) var cacheWriteFailureCount = 0

    private static let log = Logger(
        subsystem: "com.jiujiucat.pawfolio",
        category: "market-cache"
    )

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

        await withTaskGroup(of: MarketQuoteFetchResult.self) { group in
            for symbol in normalizedSymbols {
                group.addTask { [client] in
                    do {
                        return MarketQuoteFetchResult(
                            symbol: symbol,
                            quote: try await client.quote(symbol: symbol)
                        )
                    } catch {
                        return MarketQuoteFetchResult(symbol: symbol, quote: nil)
                    }
                }
            }

            for await result in group {
                if let quote = result.quote {
                    fetched[result.symbol] = quote
                } else {
                    failed.insert(result.symbol)
                }
            }
        }

        if !fetched.isEmpty {
            var updatedCache = cached
            fetched.forEach { updatedCache[$0.key] = $0.value }
            // 写不进去不影响本次结果——报价已经在手里了——但要留下痕迹。
            record { try saveCache(updatedCache) }
        }

        // 拿不到新价时一律回退到本地缓存，**不再按 12 小时把旧价丢掉**。
        // 丢掉的后果是该标的在界面上直接没有价格（调用方是整体替换），刷新几次
        // 就会看到价格忽有忽无 —— 一个过期的价格配上「来自缓存」的提示，
        // 比凭空消失要有用。failedSymbols 仍然如实包含它们，供上层提示。
        var resolved = fetched
        var usedCachedValues = false
        for symbol in failed {
            guard let cachedQuote = cached[symbol] else { continue }
            resolved[symbol] = cachedQuote
            usedCachedValues = true
        }

        return MarketQuoteRefresh(
            // 只有「网络失败且本地一个价都没有」才算真的没拿到 —— 被缓存兜住的
            // 通过 usedCachedValues 表达，两者语义不同，别合并。
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

        await withTaskGroup(of: MarketHistoryFetchResult.self) { group in
            for symbol in targets {
                group.addTask { [client] in
                    do {
                        return MarketHistoryFetchResult(
                            symbol: symbol,
                            history: try await client.oneYearHistory(symbol: symbol)
                        )
                    } catch {
                        return MarketHistoryFetchResult(symbol: symbol, history: nil)
                    }
                }
            }

            for await result in group {
                if let history = result.history {
                    fetched[result.symbol] = history
                } else {
                    failed.insert(result.symbol)
                }
            }
        }

        if !fetched.isEmpty {
            var updatedCache = cache
            fetched.forEach { updatedCache[$0.key] = $0.value }
            record { try saveHistoryCache(updatedCache) }
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

    /// 缓存写入是「尽力而为」：失败不往上抛，但要计数并落日志，别像 `try?` 那样
    /// 悄无声息。
    private func record(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            cacheWriteFailureCount += 1
            Self.log.error(
                "行情缓存写盘失败（第 \(self.cacheWriteFailureCount, privacy: .public) 次）：\(error.localizedDescription, privacy: .public)"
            )
        }
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
