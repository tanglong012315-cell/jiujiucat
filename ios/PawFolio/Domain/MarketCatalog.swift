import Foundation

/// 标的目录：代号 → 行情盘口。
///
/// 目录是**预生成的静态文件** `/catalog.json`（约 7900 只美股 + 600 多个加密，
/// gzip 后约 105KB），客户端缓存一天。搜索因此是**纯内存过滤**，不用每敲一个
/// 字母打一次请求 —— 也就没有防抖和竞态。
///
/// ⛔ 为什么不是 Worker 端点：Binance 对 Cloudflare 出口 IP 返回 403（api 和
/// bapi 两个域名都拦），OKX 返回 429，而浏览器和手机直连全部 200 —— 它们拦的
/// 是数据中心 IP。静态资源由 Cloudflare 直接分发、根本不经过 Worker，绕开封锁。
/// 生成脚本见 `scripts/build_catalog.py`。
///
/// ⚠️ 美股走的是 Binance Stocks（真实股价，代号 EQ_VOO），不是现货那套代币化
/// 股票（bStocks，代号 AAPLB）。后者是第三方发行的代币，和真实股价有 0.2~0.7%
/// 偏差，拿来给持仓估值会把那个偏差直接变成盈亏里的误差。
struct MarketCatalog: Equatable, Sendable {
    struct EquityEntry: Equatable, Sendable {
        let name: String
        let assetType: AssetType
    }

    struct CryptoEntry: Equatable, Sendable {
        /// 现货交易对。Binance 是 BTCUSDT，OKX 是 OKB-USDT。
        let pair: String
        let name: String
        /// 计价货币：USD 或 USDT。USDT 计价的要再乘一道 USDT/USD 才是美元价。
        let quoteCurrency: String
        /// 场所：binance 或 okx。
        ///
        /// 为什么需要第二家：Binance 不上架任何竞争对手的平台币 —— OKB / CRO /
        /// LEO 都没有，只有自家 BNB。单一交易所必然有这类洞。两家都没有的
        /// （BGB / HT / KCS 这些）就是不支持，取价时诚实显示，不编价格。
        let venue: String
    }

    let equities: [String: EquityEntry]
    let cryptos: [String: CryptoEntry]

    static let empty = Self(equities: [:], cryptos: [:])

    var isEmpty: Bool { equities.isEmpty && cryptos.isEmpty }

    /// 目录取不到时的最小内置表。
    ///
    /// 不是为了开发方便才有的：`/api/catalog` 一旦挂掉，App 会失去**所有**价格。
    /// 有这张表兜底，至少行情条那几个标的和稳定币折算还是活的，退化范围收敛到
    /// 「搜不到新标的」。只放最核心的几个 —— 多了就成了要人手维护的第二份真相。
    static let fallback = Self(
        equities: [
            "MSTR": EquityEntry(name: "Strategy Inc Common Stock Class A", assetType: .equity),
            "QQQ": EquityEntry(name: "Invesco QQQ Trust, Series 1", assetType: .etf)
        ],
        cryptos: [
            "BTC": CryptoEntry(pair: "BTCUSDT", name: "Bitcoin", quoteCurrency: "USDT", venue: "binance"),
            "ETH": CryptoEntry(pair: "ETHUSDT", name: "Ethereum", quoteCurrency: "USDT", venue: "binance"),
            "USDT": CryptoEntry(pair: "USDTUSD", name: "TetherUS", quoteCurrency: "USD", venue: "binance"),
            "USDC": CryptoEntry(pair: "USDCUSD", name: "USDC", quoteCurrency: "USD", venue: "binance")
        ]
    )
}

/// 解析结果：一个代号对应的具体盘口。
struct MarketInstrument: Equatable, Sendable {
    let symbol: String
    let isEquity: Bool
    /// 加密才有；美股那边的接口直接认代号。
    let pair: String?
    let quoteCurrency: String
    let name: String
    let assetType: AssetType
    /// 加密才有意义：binance / okx。美股固定走 Binance Stocks。
    let venue: String
}

extension MarketCatalog {
    /// 代号 → 盘口。
    ///
    /// 消歧规则和 Web 一致：
    /// - 带 `-USD` 后缀的一定是加密（旧持仓里存的是 Yahoo 格式的 `BTC-USD`）。
    /// - 给了 assetType 就按类型查。
    /// - 都没有时先查美股 —— 7900 多只美股比 400 多个币更可能是用户手打的目标。
    func resolve(symbol rawSymbol: String, assetType: AssetType? = nil) -> MarketInstrument? {
        let trimmed = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let hadUSDSuffix = trimmed.hasSuffix("-USD")
        let code = hadUSDSuffix ? String(trimmed.dropLast(4)) : trimmed
        guard !code.isEmpty else { return nil }

        let wantsEquity = assetType == .equity || assetType == .etf
        // STABLE 是手填生息持仓的类型，它的标的名就是 USDT / USDC 这类币。
        let wantsCrypto = hadUSDSuffix || assetType == .cryptocurrency || assetType == .stable

        if wantsCrypto, let entry = cryptos[code] { return instrument(code: code, crypto: entry) }
        if wantsEquity, let entry = equities[code] { return instrument(code: code, equity: entry) }
        if wantsCrypto || wantsEquity {
            // 明确要过某一类但没找到时，再试另一类，好过直接判定「不支持」。
            if let entry = equities[code] { return instrument(code: code, equity: entry) }
            if let entry = cryptos[code] { return instrument(code: code, crypto: entry) }
            return nil
        }
        if let entry = equities[code] { return instrument(code: code, equity: entry) }
        if let entry = cryptos[code] { return instrument(code: code, crypto: entry) }
        return nil
    }

    private func instrument(code: String, equity: EquityEntry) -> MarketInstrument {
        MarketInstrument(
            symbol: code,
            isEquity: true,
            pair: nil,
            quoteCurrency: "USD",
            name: equity.name,
            assetType: equity.assetType,
            venue: "binance"
        )
    }

    private func instrument(code: String, crypto: CryptoEntry) -> MarketInstrument {
        MarketInstrument(
            symbol: code,
            isEquity: false,
            pair: crypto.pair,
            quoteCurrency: crypto.quoteCurrency,
            name: crypto.name,
            assetType: .cryptocurrency,
            venue: crypto.venue
        )
    }

    /// 搜索。排序：代号完全匹配 > 代号前缀 > 名称前缀 > 名称包含；
    /// 同分时美股在前（覆盖面差得远，裸代号更可能是股票），再按代号长度和字典序。
    func search(_ rawQuery: String, limit: Int = 12) -> [AssetSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty else { return [] }

        var scored: [(score: Double, result: AssetSearchResult)] = []

        func rank(code: String, name: String) -> Double? {
            let upperName = name.uppercased()
            if code == query { return 0 }
            if code.hasPrefix(query) { return 1 }
            if upperName.hasPrefix(query) { return 2 }
            if upperName.contains(query) { return 3 }
            return nil
        }

        for (code, entry) in equities {
            guard let score = rank(code: code, name: entry.name) else { continue }
            scored.append((score, AssetSearchResult(
                symbol: code,
                quoteSymbol: code,
                name: entry.name,
                assetType: entry.assetType,
                exchange: "美股"
            )))
        }
        for (code, entry) in cryptos {
            guard let score = rank(code: code, name: entry.name) else { continue }
            scored.append((score + 0.5, AssetSearchResult(
                symbol: code,
                // 加密持仓历史上存的是 Yahoo 格式的 BTC-USD，这里保持一致，
                // 免得新旧两批持仓在同一个列表里出现两条 BTC。
                quoteSymbol: "\(code)-USD",
                name: entry.name,
                assetType: .cryptocurrency,
                exchange: entry.venue == "okx" ? "OKX" : "Crypto"
            )))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.result.symbol.count != rhs.result.symbol.count {
                    return lhs.result.symbol.count < rhs.result.symbol.count
                }
                return lhs.result.symbol < rhs.result.symbol
            }
            .prefix(limit)
            .map(\.result)
    }
}
