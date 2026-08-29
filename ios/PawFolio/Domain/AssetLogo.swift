import Foundation

/// 加密货币的 CoinMarketCap 数字 ID 表。由 Worker 的 `/api/crypto-logos?v=2` 下发，
/// 前端缓存一天——不在客户端硬编码映射，那份表漏得多又要人手维护。
struct CryptoLogoIndex: Codable, Equatable, Sendable {
    /// 代码 → CMC 数字 ID。
    let ids: [String: Int]
    /// 归一化后的币名 → CMC 数字 ID。
    let names: [String: Int]

    static let empty = Self(ids: [:], names: [:])
}

/// `app.js` 的 `assetLogoCandidates` 移植：给出按优先级排好的 logo 地址，
/// 由调用方按序试，第一个能加载的就用，全失败退回首字母。
enum AssetLogoCandidates {
    /// 对应 Web 的 `^[A-Z0-9]{1,20}$`。放到 20 位是因为 Yahoo 会给重名的币加数字后缀
    /// （`FARTCOIN34814`），12 位卡不住。
    ///
    /// 这里不用 `Regex`：它不是 `Sendable`，在 Swift 6 下当不了静态属性。
    private static func isTickerLike(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 20 else { return false }
        return value.allSatisfy { character in
            guard let ascii = character.asciiValue else { return false }
            return (ascii >= 65 && ascii <= 90) || (ascii >= 48 && ascii <= 57)
        }
    }

    /// 必须和 Worker 里的 `normalizeCoinName` 保持一致：两边都要能把 Yahoo 的
    /// `Render USD` 和 CMC 的 `Render` 归一成同一个 `render`。
    static func normalizeCoinName(_ value: String) -> String {
        let compact = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return compact.hasSuffix("usd") ? String(compact.dropLast(3)) : compact
    }

    private static func cmc(_ id: Int) -> URL? {
        URL(string: "https://s2.coinmarketcap.com/static/img/coins/64x64/\(id).png")
    }

    private static func coinCap(_ bare: String) -> URL? {
        URL(string: "https://assets.coincap.io/assets/icons/\(bare.lowercased())@2x.png")
    }

    /// 最后一道兜底：这套图风格不统一，仓库也早就不更新了，只用来救
    /// 「CMC 和 CoinCap 都没有」的长尾币——那种情况本来只能显示首字母。
    private static func cryptoIcons(_ bare: String) -> URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/Cryptofonts/cryptoicons@master/SVG/\(bare.lowercased()).svg")
    }

    private static func parqet(_ symbol: String) -> URL? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://assets.parqet.com/logos/symbol/\(encoded)?format=png")
    }

    private static func cryptoCandidates(
        bare: String,
        name: String,
        index: CryptoLogoIndex
    ) -> [URL] {
        guard isTickerLike(bare) else { return [] }

        // 先按代码查，查不到再按名称查。名称这条是给代码对不上的情况准备的：
        // Yahoo 的数字后缀，以及 CMC 改过代码的币（RNDR 现在叫 RENDER）。
        let byName = index.names[normalizeCoinName(name)]
        let id = index.ids[bare] ?? byName

        // 这张表是从网络上拿的，校验成正整数再拼进 URL，别把任意内容放进地址里。
        let cmcCandidate = (id.map { $0 > 0 } ?? false) ? cmc(id!) : nil

        return [cmcCandidate, coinCap(bare), cryptoIcons(bare)].compactMap(\.self)
    }

    /// 判断是不是加密货币不能只看 `assetType`：旧持仓里的加密货币没存 `-USD` 后缀，
    /// 解析时只能按后缀猜，ETH 这种会被判成股票。所以两条候选都给出去，按序试。
    static func candidates(
        quoteSymbol: String,
        assetType: AssetType,
        name: String,
        index: CryptoLogoIndex = .empty
    ) -> [URL] {
        guard !quoteSymbol.isEmpty else { return [] }

        let bare = quoteSymbol.hasSuffix("-USD")
            ? String(quoteSymbol.dropLast(4)).uppercased()
            : quoteSymbol.uppercased()

        let crypto = cryptoCandidates(bare: bare, name: name, index: index)
        let stock = parqet(quoteSymbol)

        // 稳定生息持仓填的标的名就是 USDT / USDG 这类稳定币，它们在 Parqet
        // （股票/ETF 源）永远 404，得和加密货币一样先走加密源。
        let cryptoFirst = assetType == .cryptocurrency || assetType == .stable

        if cryptoFirst {
            // 手打的名字不像代码时 crypto 是空的，这时连股票源都不用试——
            // 拿「活期」这种词去拼图片地址只会白打两次 404。
            guard !crypto.isEmpty else { return [] }
            return crypto + [stock].compactMap(\.self)
        }

        return [stock].compactMap(\.self) + crypto
    }
}
