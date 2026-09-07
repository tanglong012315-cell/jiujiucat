import Foundation

enum BundledAssetLogoSource: String, Sendable {
    case figma
    case marketSnapshot
}

struct BundledAssetLogo: Equatable, Sendable {
    let rank: Int
    let symbol: String
    let name: String
    let assetName: String
    let source: BundledAssetLogoSource
    let figmaNodeID: String?

    init(
        rank: Int,
        symbol: String,
        name: String,
        assetName: String,
        source: BundledAssetLogoSource,
        figmaNodeID: String? = nil
    ) {
        self.rank = rank
        self.symbol = symbol
        self.name = name
        self.assetName = assetName
        self.source = source
        self.figmaNodeID = figmaNodeID
    }
}

/// 2026-09-05 的市值快照。Logo 随 App 安装，本地命中后不发网络请求。
///
/// Crypto 排名来自 CoinGecko USD market-cap；股票按全球已上市公司市值排序，
/// 排除未上市的 SpaceX 后补入第 101 名 TMUS，得到可在 Yahoo 查询的 100 只股票。
/// Figma 文件存在且语义匹配明确的节点记录在 `figmaNodeID`；其余图片只作为
/// 同一快照的补齐资源。排名变化时必须整体更新清单、资源和快照日期。
enum AssetLogoCatalog {
    static let snapshotDate = "2026-09-05"
    static let figmaFileKey = "1GfyhXAMaIIJhOv2tvL4rU"

    static let crypto: [BundledAssetLogo] = [
        .init(rank: 1, symbol: "BTC", name: "Bitcoin", assetName: "AssetLogoCrypto_BTC", source: .figma, figmaNodeID: "1:59731"),
        .init(rank: 2, symbol: "ETH", name: "Ethereum", assetName: "AssetLogoCrypto_ETH", source: .figma, figmaNodeID: "1:73723"),
        .init(rank: 3, symbol: "USDT", name: "Tether", assetName: "AssetLogoCrypto_USDT", source: .figma, figmaNodeID: "1:72330"),
        .init(rank: 4, symbol: "BNB", name: "BNB", assetName: "AssetLogoCrypto_BNB", source: .figma, figmaNodeID: "1:59447"),
        .init(rank: 5, symbol: "XRP", name: "XRP", assetName: "AssetLogoCrypto_XRP", source: .figma, figmaNodeID: "1:72973"),
        .init(rank: 6, symbol: "USDC", name: "USDC", assetName: "AssetLogoCrypto_USDC", source: .figma, figmaNodeID: "1:71778"),
        .init(rank: 7, symbol: "SOL", name: "Solana", assetName: "AssetLogoCrypto_SOL", source: .figma, figmaNodeID: "1:70754"),
        .init(rank: 8, symbol: "TRX", name: "TRON", assetName: "AssetLogoCrypto_TRX", source: .figma, figmaNodeID: "1:71398"),
        .init(rank: 9, symbol: "FIGR_HELOC", name: "Figure Heloc", assetName: "AssetLogoCrypto_FIGR_HELOC", source: .marketSnapshot),
        .init(rank: 10, symbol: "HYPE", name: "Hyperliquid", assetName: "AssetLogoCrypto_HYPE", source: .figma, figmaNodeID: "1:65934"),
        .init(rank: 11, symbol: "ZEC", name: "Zcash", assetName: "AssetLogoCrypto_ZEC", source: .figma, figmaNodeID: "1:73228"),
        .init(rank: 12, symbol: "DOGE", name: "Dogecoin", assetName: "AssetLogoCrypto_DOGE", source: .figma, figmaNodeID: "1:63845"),
        .init(rank: 13, symbol: "RAIN", name: "Rain", assetName: "AssetLogoCrypto_RAIN", source: .marketSnapshot),
        .init(rank: 14, symbol: "XMR", name: "Monero", assetName: "AssetLogoCrypto_XMR", source: .figma, figmaNodeID: "1:73038"),
        .init(rank: 15, symbol: "USDS", name: "USDS", assetName: "AssetLogoCrypto_USDS", source: .marketSnapshot),
        .init(rank: 16, symbol: "LINK", name: "Chainlink", assetName: "AssetLogoCrypto_LINK", source: .figma, figmaNodeID: "1:67009"),
        .init(rank: 17, symbol: "WBT", name: "WhiteBIT Coin", assetName: "AssetLogoCrypto_WBT", source: .marketSnapshot),
        .init(rank: 18, symbol: "LEO", name: "LEO Token", assetName: "AssetLogoCrypto_LEO", source: .figma, figmaNodeID: "1:67072"),
        .init(rank: 19, symbol: "ADA", name: "Cardano", assetName: "AssetLogoCrypto_ADA", source: .figma, figmaNodeID: "1:57561"),
        .init(rank: 20, symbol: "XLM", name: "Stellar", assetName: "AssetLogoCrypto_XLM", source: .figma, figmaNodeID: "1:72981"),
        .init(rank: 21, symbol: "BCH", name: "Bitcoin Cash", assetName: "AssetLogoCrypto_BCH", source: .figma, figmaNodeID: "1:59146"),
        .init(rank: 22, symbol: "DAI", name: "Dai", assetName: "AssetLogoCrypto_DAI", source: .figma, figmaNodeID: "1:64254"),
        .init(rank: 23, symbol: "USDE", name: "Ethena USDe", assetName: "AssetLogoCrypto_USDE", source: .figma, figmaNodeID: "1:73735"),
        .init(rank: 24, symbol: "CC", name: "Canton", assetName: "AssetLogoCrypto_CC", source: .marketSnapshot),
        .init(rank: 25, symbol: "USD1", name: "USD1", assetName: "AssetLogoCrypto_USD1", source: .figma, figmaNodeID: "1:72447"),
        .init(rank: 26, symbol: "LTC", name: "Litecoin", assetName: "AssetLogoCrypto_LTC", source: .figma, figmaNodeID: "1:67003"),
        .init(rank: 27, symbol: "GRAM", name: "Gram (prev. Toncoin)", assetName: "AssetLogoCrypto_GRAM", source: .marketSnapshot),
        .init(rank: 28, symbol: "UNI", name: "Uniswap", assetName: "AssetLogoCrypto_UNI", source: .figma, figmaNodeID: "1:71793"),
        .init(rank: 29, symbol: "HBAR", name: "Hedera", assetName: "AssetLogoCrypto_HBAR", source: .figma, figmaNodeID: "1:65830"),
        .init(rank: 30, symbol: "SHIB", name: "Shiba Inu", assetName: "AssetLogoCrypto_SHIB", source: .figma, figmaNodeID: "1:70318"),
        .init(rank: 31, symbol: "SUI", name: "Sui", assetName: "AssetLogoCrypto_SUI", source: .figma, figmaNodeID: "1:70696"),
        .init(rank: 32, symbol: "USDG", name: "Global Dollar", assetName: "AssetLogoCrypto_USDG", source: .marketSnapshot),
        .init(rank: 33, symbol: "AVAX", name: "Avalanche", assetName: "AssetLogoCrypto_AVAX", source: .figma, figmaNodeID: "1:57513"),
        .init(rank: 34, symbol: "NEAR", name: "NEAR Protocol", assetName: "AssetLogoCrypto_NEAR", source: .figma, figmaNodeID: "1:68280"),
        .init(rank: 35, symbol: "PYUSD", name: "PayPal USD", assetName: "AssetLogoCrypto_PYUSD", source: .marketSnapshot),
        .init(rank: 36, symbol: "BUIDL", name: "BlackRock USD Institutional Digital Liquidity Fund", assetName: "AssetLogoCrypto_BUIDL", source: .marketSnapshot),
        .init(rank: 37, symbol: "CRO", name: "Cronos", assetName: "AssetLogoCrypto_CRO", source: .figma, figmaNodeID: "1:60130"),
        .init(rank: 38, symbol: "XAUT", name: "Tether Gold", assetName: "AssetLogoCrypto_XAUT", source: .figma, figmaNodeID: "1:72336"),
        .init(rank: 39, symbol: "USYC", name: "Circle USYC", assetName: "AssetLogoCrypto_USYC", source: .marketSnapshot),
        .init(rank: 40, symbol: "M", name: "MemeCore", assetName: "AssetLogoCrypto_M", source: .figma, figmaNodeID: "1:67896"),
        .init(rank: 41, symbol: "RLUSD", name: "Ripple USD", assetName: "AssetLogoCrypto_RLUSD", source: .marketSnapshot),
        .init(rank: 42, symbol: "OKB", name: "OKB", assetName: "AssetLogoCrypto_OKB", source: .marketSnapshot),
        .init(rank: 43, symbol: "ASTER", name: "Aster", assetName: "AssetLogoCrypto_ASTER", source: .figma, figmaNodeID: "1:58214"),
        .init(rank: 44, symbol: "TAO", name: "Bittensor", assetName: "AssetLogoCrypto_TAO", source: .figma, figmaNodeID: "1:71612"),
        .init(rank: 45, symbol: "USDY", name: "Ondo US Dollar Yield", assetName: "AssetLogoCrypto_USDY", source: .figma, figmaNodeID: "1:72345"),
        .init(rank: 46, symbol: "AAVE", name: "Aave", assetName: "AssetLogoCrypto_AAVE", source: .figma, figmaNodeID: "1:57543"),
        .init(rank: 47, symbol: "MNT", name: "Mantle", assetName: "AssetLogoCrypto_MNT", source: .figma, figmaNodeID: "1:67782"),
        .init(rank: 48, symbol: "PAXG", name: "PAX Gold", assetName: "AssetLogoCrypto_PAXG", source: .marketSnapshot),
        .init(rank: 49, symbol: "WLFI", name: "World Liberty Financial", assetName: "AssetLogoCrypto_WLFI", source: .figma, figmaNodeID: "1:72846"),
        .init(rank: 50, symbol: "ONDO", name: "Ondo", assetName: "AssetLogoCrypto_ONDO", source: .figma, figmaNodeID: "1:68594"),
        .init(rank: 51, symbol: "MORPHO", name: "Morpho", assetName: "AssetLogoCrypto_MORPHO", source: .figma, figmaNodeID: "1:67828"),
        .init(rank: 52, symbol: "ENA", name: "Ethena", assetName: "AssetLogoCrypto_ENA", source: .figma, figmaNodeID: "1:73746"),
        .init(rank: 53, symbol: "PUMP", name: "Pump.fun", assetName: "AssetLogoCrypto_PUMP", source: .figma, figmaNodeID: "1:69569"),
        .init(rank: 54, symbol: "SKY", name: "Sky", assetName: "AssetLogoCrypto_SKY", source: .figma, figmaNodeID: "1:70992"),
        .init(rank: 55, symbol: "DOT", name: "Polkadot", assetName: "AssetLogoCrypto_DOT", source: .figma, figmaNodeID: "1:63831"),
        .init(rank: 56, symbol: "PEPE", name: "Pepe", assetName: "AssetLogoCrypto_PEPE", source: .figma, figmaNodeID: "1:69511"),
        .init(rank: 57, symbol: "HTX", name: "HTX DAO", assetName: "AssetLogoCrypto_HTX", source: .marketSnapshot),
        .init(rank: 58, symbol: "USDD", name: "USDD", assetName: "AssetLogoCrypto_USDD", source: .figma, figmaNodeID: "1:72410"),
        .init(rank: 59, symbol: "WLD", name: "Worldcoin", assetName: "AssetLogoCrypto_WLD", source: .figma, figmaNodeID: "1:72775"),
        .init(rank: 60, symbol: "ICP", name: "Internet Computer", assetName: "AssetLogoCrypto_ICP", source: .figma, figmaNodeID: "1:66183"),
        .init(rank: 61, symbol: "BGB", name: "Bitget Token", assetName: "AssetLogoCrypto_BGB", source: .marketSnapshot),
        .init(rank: 62, symbol: "USDGO", name: "USDGO", assetName: "AssetLogoCrypto_USDGO", source: .marketSnapshot),
        .init(rank: 63, symbol: "USDF", name: "Falcon USD", assetName: "AssetLogoCrypto_USDF", source: .marketSnapshot),
        .init(rank: 64, symbol: "BFUSD", name: "BFUSD", assetName: "AssetLogoCrypto_BFUSD", source: .figma, figmaNodeID: "1:59714"),
        .init(rank: 65, symbol: "U", name: "United Stables", assetName: "AssetLogoCrypto_U", source: .figma, figmaNodeID: "1:72446"),
        .init(rank: 66, symbol: "ETC", name: "Ethereum Classic", assetName: "AssetLogoCrypto_ETC", source: .figma, figmaNodeID: "1:73645"),
        .init(rank: 67, symbol: "EURSAFO", name: "Spiko Amundi Overnight Swap Fund (EUR)", assetName: "AssetLogoCrypto_EURSAFO", source: .marketSnapshot),
        .init(rank: 68, symbol: "BTW", name: "Bitway", assetName: "AssetLogoCrypto_BTW", source: .figma, figmaNodeID: "1:59868"),
        .init(rank: 69, symbol: "LIT", name: "Lighter", assetName: "AssetLogoCrypto_LIT", source: .figma, figmaNodeID: "1:67241"),
        .init(rank: 70, symbol: "PI", name: "Pi Network", assetName: "AssetLogoCrypto_PI", source: .marketSnapshot),
        .init(rank: 71, symbol: "POL", name: "POL (ex-MATIC)", assetName: "AssetLogoCrypto_POL", source: .figma, figmaNodeID: "1:69356"),
        .init(rank: 72, symbol: "KCS", name: "KuCoin", assetName: "AssetLogoCrypto_KCS", source: .figma, figmaNodeID: "1:66479"),
        .init(rank: 73, symbol: "BCAP", name: "Blockchain Capital", assetName: "AssetLogoCrypto_BCAP", source: .marketSnapshot),
        .init(rank: 74, symbol: "GT", name: "Gate", assetName: "AssetLogoCrypto_GT", source: .figma, figmaNodeID: "1:64505"),
        .init(rank: 75, symbol: "QNT", name: "Quant", assetName: "AssetLogoCrypto_QNT", source: .figma, figmaNodeID: "1:69765"),
        .init(rank: 76, symbol: "ARB", name: "Arbitrum", assetName: "AssetLogoCrypto_ARB", source: .figma, figmaNodeID: "1:57894"),
        .init(rank: 77, symbol: "JST", name: "JUST", assetName: "AssetLogoCrypto_JST", source: .figma, figmaNodeID: "1:66468"),
        .init(rank: 78, symbol: "EUTBL", name: "Spiko EU T-Bills Money Market Fund", assetName: "AssetLogoCrypto_EUTBL", source: .marketSnapshot),
        .init(rank: 79, symbol: "ALGO", name: "Algorand", assetName: "AssetLogoCrypto_ALGO", source: .figma, figmaNodeID: "1:57447"),
        .init(rank: 80, symbol: "DASH", name: "Dash", assetName: "AssetLogoCrypto_DASH", source: .figma, figmaNodeID: "1:63850"),
        .init(rank: 81, symbol: "VVV", name: "Venice Token", assetName: "AssetLogoCrypto_VVV", source: .figma, figmaNodeID: "1:72639"),
        .init(rank: 82, symbol: "KAS", name: "Kaspa", assetName: "AssetLogoCrypto_KAS", source: .figma, figmaNodeID: "1:66570"),
        .init(rank: 83, symbol: "NEXO", name: "NEXO", assetName: "AssetLogoCrypto_NEXO", source: .figma, figmaNodeID: "1:68021"),
        .init(rank: 84, symbol: "ATOM", name: "Cosmos Hub", assetName: "AssetLogoCrypto_ATOM", source: .figma, figmaNodeID: "1:57409"),
        .init(rank: 85, symbol: "JTRSY", name: "Janus Henderson Anemoy Treasury Fund", assetName: "AssetLogoCrypto_JTRSY", source: .marketSnapshot),
        .init(rank: 86, symbol: "USTB", name: "Invesco Short Duration US Government Securities Fund", assetName: "AssetLogoCrypto_USTB", source: .marketSnapshot),
        .init(rank: 87, symbol: "RENDER", name: "Render", assetName: "AssetLogoCrypto_RENDER", source: .figma, figmaNodeID: "1:70010"),
        .init(rank: 88, symbol: "STABLE", name: "​​Stable", assetName: "AssetLogoCrypto_STABLE", source: .figma, figmaNodeID: "1:71215"),
        .init(rank: 89, symbol: "JUP", name: "Jupiter", assetName: "AssetLogoCrypto_JUP", source: .figma, figmaNodeID: "1:66427"),
        .init(rank: 90, symbol: "CAKE", name: "PancakeSwap", assetName: "AssetLogoCrypto_CAKE", source: .figma, figmaNodeID: "1:60220"),
        .init(rank: 91, symbol: "JAAA", name: "Janus Henderson Anemoy AAA CLO Fund", assetName: "AssetLogoCrypto_JAAA", source: .marketSnapshot),
        .init(rank: 92, symbol: "GHO", name: "GHO", assetName: "AssetLogoCrypto_GHO", source: .marketSnapshot),
        .init(rank: 93, symbol: "FIL", name: "Filecoin", assetName: "AssetLogoCrypto_FIL", source: .figma, figmaNodeID: "1:73960"),
        .init(rank: 94, symbol: "PONS", name: "Pons", assetName: "AssetLogoCrypto_PONS", source: .marketSnapshot),
        .init(rank: 95, symbol: "TRUMP", name: "Official Trump", assetName: "AssetLogoCrypto_TRUMP", source: .figma, figmaNodeID: "1:71628"),
        .init(rank: 96, symbol: "BDX", name: "Beldex", assetName: "AssetLogoCrypto_BDX", source: .marketSnapshot),
        .init(rank: 97, symbol: "VET", name: "VeChain", assetName: "AssetLogoCrypto_VET", source: .figma, figmaNodeID: "1:72490"),
        .init(rank: 98, symbol: "FLR", name: "Flare", assetName: "AssetLogoCrypto_FLR", source: .figma, figmaNodeID: "1:74028"),
        .init(rank: 99, symbol: "CRV", name: "Curve DAO", assetName: "AssetLogoCrypto_CRV", source: .figma, figmaNodeID: "1:60398"),
        .init(rank: 100, symbol: "XDC", name: "XDC Network", assetName: "AssetLogoCrypto_XDC", source: .marketSnapshot)
    ]

    static let stocks: [BundledAssetLogo] = [
        .init(rank: 1, symbol: "NVDA", name: "NVIDIA", assetName: "AssetLogoStock_NVDA", source: .figma, figmaNodeID: "1:68275"),
        .init(rank: 2, symbol: "AAPL", name: "Apple", assetName: "AssetLogoStock_AAPL", source: .figma, figmaNodeID: "1:57384"),
        .init(rank: 3, symbol: "GOOG", name: "Alphabet (Google)", assetName: "AssetLogoStock_GOOG", source: .figma, figmaNodeID: "1:65724"),
        .init(rank: 4, symbol: "MSFT", name: "Microsoft", assetName: "AssetLogoStock_MSFT", source: .figma, figmaNodeID: "1:67540"),
        .init(rank: 5, symbol: "AMZN", name: "Amazon", assetName: "AssetLogoStock_AMZN", source: .figma, figmaNodeID: "1:58272"),
        .init(rank: 6, symbol: "TSM", name: "TSMC", assetName: "AssetLogoStock_TSM", source: .figma, figmaNodeID: "1:71736"),
        .init(rank: 7, symbol: "AVGO", name: "Broadcom", assetName: "AssetLogoStock_AVGO", source: .figma, figmaNodeID: "1:58288"),
        .init(rank: 8, symbol: "2222.SR", name: "Saudi Aramco", assetName: "AssetLogoStock_2222_SR", source: .marketSnapshot),
        .init(rank: 9, symbol: "META", name: "Meta Platforms (Facebook)", assetName: "AssetLogoStock_META", source: .marketSnapshot),
        .init(rank: 10, symbol: "TSLA", name: "Tesla", assetName: "AssetLogoStock_TSLA", source: .figma, figmaNodeID: "1:71373"),
        .init(rank: 11, symbol: "005930.KS", name: "Samsung", assetName: "AssetLogoStock_005930_KS", source: .marketSnapshot),
        .init(rank: 12, symbol: "MU", name: "Micron Technology", assetName: "AssetLogoStock_MU", source: .marketSnapshot),
        .init(rank: 13, symbol: "BRK-B", name: "Berkshire Hathaway", assetName: "AssetLogoStock_BRK_B", source: .marketSnapshot),
        .init(rank: 14, symbol: "LLY", name: "Eli Lilly", assetName: "AssetLogoStock_LLY", source: .marketSnapshot),
        .init(rank: 15, symbol: "JPM", name: "JPMorgan Chase", assetName: "AssetLogoStock_JPM", source: .marketSnapshot),
        .init(rank: 16, symbol: "000660.KS", name: "SK Hynix", assetName: "AssetLogoStock_000660_KS", source: .marketSnapshot),
        .init(rank: 17, symbol: "WMT", name: "Walmart", assetName: "AssetLogoStock_WMT", source: .marketSnapshot),
        .init(rank: 18, symbol: "AMD", name: "AMD", assetName: "AssetLogoStock_AMD", source: .marketSnapshot),
        .init(rank: 19, symbol: "V", name: "Visa", assetName: "AssetLogoStock_V", source: .marketSnapshot),
        .init(rank: 20, symbol: "JNJ", name: "Johnson & Johnson", assetName: "AssetLogoStock_JNJ", source: .marketSnapshot),
        .init(rank: 21, symbol: "ASML", name: "ASML", assetName: "AssetLogoStock_ASML", source: .marketSnapshot),
        .init(rank: 22, symbol: "XOM", name: "Exxon Mobil", assetName: "AssetLogoStock_XOM", source: .marketSnapshot),
        .init(rank: 23, symbol: "688825.SS", name: "CXMT", assetName: "AssetLogoStock_688825_SS", source: .marketSnapshot),
        .init(rank: 24, symbol: "TCEHY", name: "Tencent", assetName: "AssetLogoStock_TCEHY", source: .marketSnapshot),
        .init(rank: 25, symbol: "MA", name: "Mastercard", assetName: "AssetLogoStock_MA", source: .marketSnapshot),
        .init(rank: 26, symbol: "INTC", name: "Intel", assetName: "AssetLogoStock_INTC", source: .figma, figmaNodeID: "1:66302"),
        .init(rank: 27, symbol: "ORCL", name: "Oracle", assetName: "AssetLogoStock_ORCL", source: .marketSnapshot),
        .init(rank: 28, symbol: "ABBV", name: "AbbVie", assetName: "AssetLogoStock_ABBV", source: .marketSnapshot),
        .init(rank: 29, symbol: "BAC", name: "Bank of America", assetName: "AssetLogoStock_BAC", source: .marketSnapshot),
        .init(rank: 30, symbol: "CSCO", name: "Cisco", assetName: "AssetLogoStock_CSCO", source: .marketSnapshot),
        .init(rank: 31, symbol: "601939.SS", name: "China Construction Bank", assetName: "AssetLogoStock_601939_SS", source: .marketSnapshot),
        .init(rank: 32, symbol: "PLTR", name: "Palantir", assetName: "AssetLogoStock_PLTR", source: .marketSnapshot),
        .init(rank: 33, symbol: "CVX", name: "Chevron", assetName: "AssetLogoStock_CVX", source: .marketSnapshot),
        .init(rank: 34, symbol: "COST", name: "Costco", assetName: "AssetLogoStock_COST", source: .marketSnapshot),
        .init(rank: 35, symbol: "LRCX", name: "Lam Research", assetName: "AssetLogoStock_LRCX", source: .marketSnapshot),
        .init(rank: 36, symbol: "KO", name: "Coca-Cola", assetName: "AssetLogoStock_KO", source: .marketSnapshot),
        .init(rank: 37, symbol: "CAT", name: "Caterpillar", assetName: "AssetLogoStock_CAT", source: .marketSnapshot),
        .init(rank: 38, symbol: "MRK", name: "Merck", assetName: "AssetLogoStock_MRK", source: .marketSnapshot),
        .init(rank: 39, symbol: "HSBC", name: "HSBC", assetName: "AssetLogoStock_HSBC", source: .marketSnapshot),
        .init(rank: 40, symbol: "601288.SS", name: "Agricultural Bank of China", assetName: "AssetLogoStock_601288_SS", source: .marketSnapshot),
        .init(rank: 41, symbol: "AMAT", name: "Applied Materials", assetName: "AssetLogoStock_AMAT", source: .marketSnapshot),
        .init(rank: 42, symbol: "RO.SW", name: "Roche", assetName: "AssetLogoStock_RO_SW", source: .marketSnapshot),
        .init(rank: 43, symbol: "UNH", name: "UnitedHealth", assetName: "AssetLogoStock_UNH", source: .marketSnapshot),
        .init(rank: 44, symbol: "GE", name: "General Electric", assetName: "AssetLogoStock_GE", source: .marketSnapshot),
        .init(rank: 45, symbol: "1398.HK", name: "ICBC", assetName: "AssetLogoStock_1398_HK", source: .marketSnapshot),
        .init(rank: 46, symbol: "MS", name: "Morgan Stanley", assetName: "AssetLogoStock_MS", source: .marketSnapshot),
        .init(rank: 47, symbol: "PG", name: "Procter & Gamble", assetName: "AssetLogoStock_PG", source: .marketSnapshot),
        .init(rank: 48, symbol: "DELL", name: "Dell", assetName: "AssetLogoStock_DELL", source: .marketSnapshot),
        .init(rank: 49, symbol: "NFLX", name: "Netflix", assetName: "AssetLogoStock_NFLX", source: .marketSnapshot),
        .init(rank: 50, symbol: "HD", name: "Home Depot", assetName: "AssetLogoStock_HD", source: .marketSnapshot),
        .init(rank: 51, symbol: "601988.SS", name: "Bank of China", assetName: "AssetLogoStock_601988_SS", source: .marketSnapshot),
        .init(rank: 52, symbol: "NVS", name: "Novartis", assetName: "AssetLogoStock_NVS", source: .marketSnapshot),
        .init(rank: 53, symbol: "GS", name: "Goldman Sachs", assetName: "AssetLogoStock_GS", source: .marketSnapshot),
        .init(rank: 54, symbol: "RY", name: "Royal Bank Of Canada", assetName: "AssetLogoStock_RY", source: .marketSnapshot),
        .init(rank: 55, symbol: "PM", name: "Philip Morris International", assetName: "AssetLogoStock_PM", source: .marketSnapshot),
        .init(rank: 56, symbol: "BABA", name: "Alibaba", assetName: "AssetLogoStock_BABA", source: .marketSnapshot),
        .init(rank: 57, symbol: "WFC", name: "Wells Fargo", assetName: "AssetLogoStock_WFC", source: .marketSnapshot),
        .init(rank: 58, symbol: "PANW", name: "Palo Alto Networks", assetName: "AssetLogoStock_PANW", source: .marketSnapshot),
        .init(rank: 59, symbol: "MUFG", name: "Mitsubishi UFJ Financial", assetName: "AssetLogoStock_MUFG", source: .marketSnapshot),
        .init(rank: 60, symbol: "RTX", name: "RTX", assetName: "AssetLogoStock_RTX", source: .marketSnapshot),
        .init(rank: 61, symbol: "ARM", name: "Arm Holdings", assetName: "AssetLogoStock_ARM", source: .marketSnapshot),
        .init(rank: 62, symbol: "SHEL", name: "Shell", assetName: "AssetLogoStock_SHEL", source: .marketSnapshot),
        .init(rank: 63, symbol: "SNDK", name: "Sandisk", assetName: "AssetLogoStock_SNDK", source: .marketSnapshot),
        .init(rank: 64, symbol: "AZN", name: "AstraZeneca", assetName: "AssetLogoStock_AZN", source: .marketSnapshot),
        .init(rank: 65, symbol: "GEV", name: "GE Vernova", assetName: "AssetLogoStock_GEV", source: .marketSnapshot),
        .init(rank: 66, symbol: "NESN.SW", name: "Nestlé", assetName: "AssetLogoStock_NESN_SW", source: .marketSnapshot),
        .init(rank: 67, symbol: "SAP", name: "SAP", assetName: "AssetLogoStock_SAP", source: .marketSnapshot),
        .init(rank: 68, symbol: "600519.SS", name: "Kweichow Moutai", assetName: "AssetLogoStock_600519_SS", source: .marketSnapshot),
        .init(rank: 69, symbol: "SIE.DE", name: "Siemens", assetName: "AssetLogoStock_SIE_DE", source: .marketSnapshot),
        .init(rank: 70, symbol: "MC.PA", name: "LVMH", assetName: "AssetLogoStock_MC_PA", source: .marketSnapshot),
        .init(rank: 71, symbol: "ANET", name: "Arista Networks", assetName: "AssetLogoStock_ANET", source: .marketSnapshot),
        .init(rank: 72, symbol: "KLAC", name: "KLA", assetName: "AssetLogoStock_KLAC", source: .marketSnapshot),
        .init(rank: 73, symbol: "300750.SZ", name: "CATL", assetName: "AssetLogoStock_300750_SZ", source: .marketSnapshot),
        .init(rank: 74, symbol: "OR.PA", name: "L'Oréal", assetName: "AssetLogoStock_OR_PA", source: .marketSnapshot),
        .init(rank: 75, symbol: "0857.HK", name: "PetroChina", assetName: "AssetLogoStock_0857_HK", source: .marketSnapshot),
        .init(rank: 76, symbol: "AMGN", name: "Amgen", assetName: "AssetLogoStock_AMGN", source: .marketSnapshot),
        .init(rank: 77, symbol: "TXN", name: "Texas Instruments", assetName: "AssetLogoStock_TXN", source: .marketSnapshot),
        .init(rank: 78, symbol: "TM", name: "Toyota", assetName: "AssetLogoStock_TM", source: .marketSnapshot),
        .init(rank: 79, symbol: "C", name: "Citigroup", assetName: "AssetLogoStock_C", source: .marketSnapshot),
        .init(rank: 80, symbol: "BHP", name: "BHP Group", assetName: "AssetLogoStock_BHP", source: .marketSnapshot),
        .init(rank: 81, symbol: "TMO", name: "Thermo Fisher Scientific", assetName: "AssetLogoStock_TMO", source: .marketSnapshot),
        .init(rank: 82, symbol: "2454.TW", name: "MediaTek", assetName: "AssetLogoStock_2454_TW", source: .marketSnapshot),
        .init(rank: 83, symbol: "IBM", name: "IBM", assetName: "AssetLogoStock_IBM", source: .marketSnapshot),
        .init(rank: 84, symbol: "IHC.AE", name: "International Holding Company", assetName: "AssetLogoStock_IHC_AE", source: .marketSnapshot),
        .init(rank: 85, symbol: "0941.HK", name: "China Mobile", assetName: "AssetLogoStock_0941_HK", source: .marketSnapshot),
        .init(rank: 86, symbol: "AXP", name: "American Express", assetName: "AssetLogoStock_AXP", source: .marketSnapshot),
        .init(rank: 87, symbol: "LIN", name: "Linde", assetName: "AssetLogoStock_LIN", source: .marketSnapshot),
        .init(rank: 88, symbol: "CRWD", name: "CrowdStrike", assetName: "AssetLogoStock_CRWD", source: .marketSnapshot),
        .init(rank: 89, symbol: "SAN", name: "Santander", assetName: "AssetLogoStock_SAN", source: .marketSnapshot),
        .init(rank: 90, symbol: "CRM", name: "Salesforce", assetName: "AssetLogoStock_CRM", source: .marketSnapshot),
        .init(rank: 91, symbol: "VZ", name: "Verizon", assetName: "AssetLogoStock_VZ", source: .marketSnapshot),
        .init(rank: 92, symbol: "ITX.MC", name: "Inditex", assetName: "AssetLogoStock_ITX_MC", source: .marketSnapshot),
        .init(rank: 93, symbol: "NVO", name: "Novo Nordisk", assetName: "AssetLogoStock_NVO", source: .marketSnapshot),
        .init(rank: 94, symbol: "APH", name: "Amphenol", assetName: "AssetLogoStock_APH", source: .marketSnapshot),
        .init(rank: 95, symbol: "9984.T", name: "SoftBank Group Corp.", assetName: "AssetLogoStock_9984_T", source: .marketSnapshot),
        .init(rank: 96, symbol: "MRVL", name: "Marvell Technology", assetName: "AssetLogoStock_MRVL", source: .marketSnapshot),
        .init(rank: 97, symbol: "TD", name: "Toronto Dominion Bank", assetName: "AssetLogoStock_TD", source: .marketSnapshot),
        .init(rank: 98, symbol: "ALV.DE", name: "Allianz SE", assetName: "AssetLogoStock_ALV_DE", source: .marketSnapshot),
        .init(rank: 99, symbol: "TTE", name: "TotalEnergies", assetName: "AssetLogoStock_TTE", source: .marketSnapshot),
        .init(rank: 100, symbol: "TMUS", name: "T-Mobile US", assetName: "AssetLogoStock_TMUS", source: .marketSnapshot)
    ]

    /// 用户明确提供、但不属于上方 Top 100 市值快照的常用股票资源。
    /// 单独维护可避免补充资源改变快照数量或排名语义。
    static let supplementalStocks: [String: String] = [
        "MSTR": "AssetLogoStock_MSTR",
        "STRC": "AssetLogoStock_STRC"
    ]

    private static let cryptoBySymbol = Dictionary(
        uniqueKeysWithValues: crypto.map { ($0.symbol, $0.assetName) }
    )
    private static let stockBySymbol: [String: String] = {
        var result = Dictionary(
            uniqueKeysWithValues: stocks.map { ($0.symbol, $0.assetName) }
        )
        result.merge(supplementalStocks) { snapshotAsset, _ in snapshotAsset }
        return result
    }()

    private static let cryptoAliases: [String: String] = [
        "MATIC": "POL",
        "RNDR": "RENDER",
        "TON": "GRAM"
    ]

    /// Yahoo 在不同市场或股类会返回不同写法；都复用同一公司资源。
    private static let stockAliases: [String: String] = [
        "BRK.B": "BRK-B",
        "GOOGL": "GOOG",
        "0700.HK": "TCEHY",
        "9988.HK": "BABA",
        "2330.TW": "TSM",
        "7203.T": "TM",
        "SAP.DE": "SAP",
        "ROG.SW": "RO.SW"
    ]

    static func assetName(
        quoteSymbol: String,
        assetType: AssetType,
        name _: String = ""
    ) -> String? {
        let normalized = quoteSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalized.isEmpty else { return nil }

        let cryptoSymbol = normalized.hasSuffix("-USD")
            ? String(normalized.dropLast(4))
            : normalized

        switch assetType {
        case .cryptocurrency, .stable:
            return cryptoAssetName(for: cryptoSymbol)
                ?? stockAssetName(for: normalized)
        case .equity, .etf:
            // 旧 payload 偶尔把无后缀 Crypto 记成股票；股票清单找不到时再补查 Crypto。
            return stockAssetName(for: normalized)
                ?? cryptoAssetName(for: cryptoSymbol)
        }
    }

    private static func cryptoAssetName(for symbol: String) -> String? {
        let canonical = cryptoAliases[symbol] ?? symbol
        return cryptoBySymbol[canonical]
    }

    private static func stockAssetName(for symbol: String) -> String? {
        let canonical = stockAliases[symbol] ?? symbol
        return stockBySymbol[canonical]
    }
}
