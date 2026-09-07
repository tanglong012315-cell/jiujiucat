import Foundation

/// 一种法币：代码、名字、发行地，以及宿主资源目录里那面圆形国旗。
struct CurrencyInfo: Identifiable, Hashable, Sendable {
    let code: CurrencyCode
    /// 货币全名，例如 `US Dollar`。
    let name: String
    /// 发行国家或地区，例如 `United States`。副标题和搜索都用它。
    let region: String
    /// `Assets.xcassets` 里的国旗名，例如 `FlagUS`。
    let flagAssetName: String

    var id: CurrencyCode { code }

    /// 使用系统的 ISO 4217 译名，跟随 App 内注入的 Locale，而不是设备语言。
    /// 这样“美元 / 人民币 / 日元”等名称采用系统金融术语，同时英文界面仍保留
    /// 静态目录里的产品文案作为兜底。
    func localizedName(locale: Locale) -> String {
        locale.localizedString(forCurrencyCode: code.rawValue) ?? name
    }

    /// 搜索命中：代码、货币名、地区任意一个前缀或子串匹配都算。
    func matches(_ query: String, locale: Locale = .current) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return code.rawValue.lowercased().contains(needle)
            || name.lowercased().contains(needle)
            || localizedName(locale: locale).lowercased().contains(needle)
            || region.lowercased().contains(needle)
    }
}

/// 稳定币不是法币，单独维护它们的展示资料，避免污染法币汇率目录。
struct StablecoinInfo: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let logoAssetName: String

    var id: String { code }
}

/// 「Add Currency」里置顶的常用稳定币。品牌图从 PawFolio 团队的 Figma Logo 文件导出后
/// 随 App 打包；运行时不直连 Figma：`1GfyhXAMaIIJhOv2tvL4rU`。
enum StablecoinCatalog {
    /// `favorites` 只决定 Add Currency 顶部展示哪两项，不能拿它当稳定币全集。
    /// Earn 的资金账户路由必须覆盖资产目录中其余稳定币，否则 USDG 等会被误判成
    /// Crypto，进而错误地去 Trading 账户查询余额。
    static let knownCodes: Set<String> = [
        "BFUSD", "DAI", "FDUSD", "FRAX", "GHO", "GUSD", "PYUSD", "RLUSD",
        "TUSD", "U", "USD1", "USDC", "USDD", "USDE", "USDF", "USDG", "USDGO", "USDP",
        "USDS", "USDT"
    ]

    static let favorites: [StablecoinInfo] = [
        StablecoinInfo(code: "USDT", name: "Tether USD", logoAssetName: "LogoUSDT"),
        StablecoinInfo(code: "USDC", name: "Circle USD", logoAssetName: "LogoUSDC")
    ]

    private static let index = Dictionary(
        uniqueKeysWithValues: favorites.map { ($0.code, $0) }
    )

    static func info(for code: String) -> StablecoinInfo? {
        index[code.uppercased()]
    }

    static func isKnown(_ code: String) -> Bool {
        knownCodes.contains(code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }
}

/// 静态币种表。
///
/// **只收录有国旗图的法币**（用户 2026-09-03 的要求）：这张表就是「添加货币」页
/// 的全集，每一条都必须在 `Assets.xcassets` 里有对应的 `Flag*` 图，否则列表会出现
/// 一个空洞。国旗全部来自 Nvwa 设计库的 Flags section（`2013:5416`）。
///
/// 欧元区各国共用 `EUR` 一条、配欧盟旗，不为每个成员国单开一行——它们的汇率完全
/// 相同，列出来只会让用户在二十多个一模一样的条目里挑。
enum CurrencyCatalog {
    /// 汇率页首次打开时的四条，沿用 V1.1 的顺序。
    static let defaultSelection: [CurrencyCode] = [.cny, .myr, .usd, .thb]

    /// 查不到国旗时的兜底图（Flags section 里的 "No Flag"）。
    static let unknownFlagAssetName = "FlagUnknown"

    /// 按货币代码字母序排列——「添加货币」页的字母索引直接吃这个顺序。
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "AED", name: "UAE Dirham", region: "United Arab Emirates", flagAssetName: "FlagAE"),
        CurrencyInfo(code: "ARS", name: "Argentine Peso", region: "Argentina", flagAssetName: "FlagAR"),
        CurrencyInfo(code: "AUD", name: "Australian Dollar", region: "Australia", flagAssetName: "FlagAU"),
        CurrencyInfo(code: "BDT", name: "Bangladeshi Taka", region: "Bangladesh", flagAssetName: "FlagBD"),
        CurrencyInfo(code: "BGN", name: "Bulgarian Lev", region: "Bulgaria", flagAssetName: "FlagBG"),
        CurrencyInfo(code: "BHD", name: "Bahraini Dinar", region: "Bahrain", flagAssetName: "FlagBH"),
        CurrencyInfo(code: "BND", name: "Brunei Dollar", region: "Brunei", flagAssetName: "FlagBN"),
        CurrencyInfo(code: "BRL", name: "Brazilian Real", region: "Brazil", flagAssetName: "FlagBR"),
        CurrencyInfo(code: "BWP", name: "Botswana Pula", region: "Botswana", flagAssetName: "FlagBW"),
        CurrencyInfo(code: "CAD", name: "Canadian Dollar", region: "Canada", flagAssetName: "FlagCA"),
        CurrencyInfo(code: "CHF", name: "Swiss Franc", region: "Switzerland", flagAssetName: "FlagCH"),
        CurrencyInfo(code: "CLP", name: "Chilean Peso", region: "Chile", flagAssetName: "FlagCL"),
        CurrencyInfo(code: "CNY", name: "Chinese Yuan", region: "China", flagAssetName: "FlagCN"),
        CurrencyInfo(code: "COP", name: "Colombian Peso", region: "Colombia", flagAssetName: "FlagCO"),
        CurrencyInfo(code: "CRC", name: "Costa Rican Colón", region: "Costa Rica", flagAssetName: "FlagCR"),
        CurrencyInfo(code: "CZK", name: "Czech Koruna", region: "Czechia", flagAssetName: "FlagCZ"),
        CurrencyInfo(code: "DKK", name: "Danish Krone", region: "Denmark", flagAssetName: "FlagDK"),
        CurrencyInfo(code: "EGP", name: "Egyptian Pound", region: "Egypt", flagAssetName: "FlagEG"),
        CurrencyInfo(code: "EUR", name: "Euro", region: "Eurozone", flagAssetName: "FlagEU"),
        CurrencyInfo(code: "GBP", name: "British Pound", region: "United Kingdom", flagAssetName: "FlagGB"),
        CurrencyInfo(code: "GEL", name: "Georgian Lari", region: "Georgia", flagAssetName: "FlagGE"),
        CurrencyInfo(code: "GHS", name: "Ghanaian Cedi", region: "Ghana", flagAssetName: "FlagGH"),
        CurrencyInfo(code: "HKD", name: "Hong Kong Dollar", region: "Hong Kong", flagAssetName: "FlagHK"),
        CurrencyInfo(code: "HUF", name: "Hungarian Forint", region: "Hungary", flagAssetName: "FlagHU"),
        CurrencyInfo(code: "IDR", name: "Indonesian Rupiah", region: "Indonesia", flagAssetName: "FlagID"),
        CurrencyInfo(code: "ILS", name: "Israeli New Shekel", region: "Israel", flagAssetName: "FlagIL"),
        CurrencyInfo(code: "INR", name: "Indian Rupee", region: "India", flagAssetName: "FlagIN"),
        CurrencyInfo(code: "ISK", name: "Icelandic Króna", region: "Iceland", flagAssetName: "FlagIS"),
        CurrencyInfo(code: "JMD", name: "Jamaican Dollar", region: "Jamaica", flagAssetName: "FlagJM"),
        CurrencyInfo(code: "JPY", name: "Japanese Yen", region: "Japan", flagAssetName: "FlagJP"),
        CurrencyInfo(code: "KES", name: "Kenyan Shilling", region: "Kenya", flagAssetName: "FlagKE"),
        CurrencyInfo(code: "KRW", name: "South Korean Won", region: "South Korea", flagAssetName: "FlagKR"),
        CurrencyInfo(code: "KWD", name: "Kuwaiti Dinar", region: "Kuwait", flagAssetName: "FlagKW"),
        CurrencyInfo(code: "LAK", name: "Lao Kip", region: "Laos", flagAssetName: "FlagLA"),
        CurrencyInfo(code: "LKR", name: "Sri Lankan Rupee", region: "Sri Lanka", flagAssetName: "FlagLK"),
        CurrencyInfo(code: "LSL", name: "Lesotho Loti", region: "Lesotho", flagAssetName: "FlagLS"),
        CurrencyInfo(code: "MAD", name: "Moroccan Dirham", region: "Morocco", flagAssetName: "FlagMA"),
        CurrencyInfo(code: "MUR", name: "Mauritian Rupee", region: "Mauritius", flagAssetName: "FlagMU"),
        CurrencyInfo(code: "MXN", name: "Mexican Peso", region: "Mexico", flagAssetName: "FlagMX"),
        CurrencyInfo(code: "MYR", name: "Malaysian Ringgit", region: "Malaysia", flagAssetName: "FlagMY"),
        CurrencyInfo(code: "MZN", name: "Mozambican Metical", region: "Mozambique", flagAssetName: "FlagMZ"),
        CurrencyInfo(code: "NAD", name: "Namibian Dollar", region: "Namibia", flagAssetName: "FlagNA"),
        CurrencyInfo(code: "NGN", name: "Nigerian Naira", region: "Nigeria", flagAssetName: "FlagNG"),
        CurrencyInfo(code: "NOK", name: "Norwegian Krone", region: "Norway", flagAssetName: "FlagNO"),
        CurrencyInfo(code: "NPR", name: "Nepalese Rupee", region: "Nepal", flagAssetName: "FlagNP"),
        CurrencyInfo(code: "NZD", name: "New Zealand Dollar", region: "New Zealand", flagAssetName: "FlagNZ"),
        CurrencyInfo(code: "OMR", name: "Omani Rial", region: "Oman", flagAssetName: "FlagOM"),
        CurrencyInfo(code: "PAB", name: "Panamanian Balboa", region: "Panama", flagAssetName: "FlagPA"),
        CurrencyInfo(code: "PEN", name: "Peruvian Sol", region: "Peru", flagAssetName: "FlagPE"),
        CurrencyInfo(code: "PHP", name: "Philippine Peso", region: "Philippines", flagAssetName: "FlagPH"),
        CurrencyInfo(code: "PKR", name: "Pakistani Rupee", region: "Pakistan", flagAssetName: "FlagPK"),
        CurrencyInfo(code: "PLN", name: "Polish Zloty", region: "Poland", flagAssetName: "FlagPL"),
        CurrencyInfo(code: "QAR", name: "Qatari Riyal", region: "Qatar", flagAssetName: "FlagQA"),
        CurrencyInfo(code: "RON", name: "Romanian Leu", region: "Romania", flagAssetName: "FlagRO"),
        CurrencyInfo(code: "RUB", name: "Russian Ruble", region: "Russia", flagAssetName: "FlagRU"),
        CurrencyInfo(code: "SAR", name: "Saudi Riyal", region: "Saudi Arabia", flagAssetName: "FlagSA"),
        CurrencyInfo(code: "SEK", name: "Swedish Krona", region: "Sweden", flagAssetName: "FlagSE"),
        CurrencyInfo(code: "SGD", name: "Singapore Dollar", region: "Singapore", flagAssetName: "FlagSG"),
        CurrencyInfo(code: "THB", name: "Thai Baht", region: "Thailand", flagAssetName: "FlagTH"),
        CurrencyInfo(code: "TMT", name: "Turkmenistani Manat", region: "Turkmenistan", flagAssetName: "FlagTM"),
        CurrencyInfo(code: "TRY", name: "Turkish Lira", region: "Türkiye", flagAssetName: "FlagTR"),
        CurrencyInfo(code: "TWD", name: "New Taiwan Dollar", region: "Taiwan", flagAssetName: "FlagTW"),
        CurrencyInfo(code: "TZS", name: "Tanzanian Shilling", region: "Tanzania", flagAssetName: "FlagTZ"),
        CurrencyInfo(code: "UAH", name: "Ukrainian Hryvnia", region: "Ukraine", flagAssetName: "FlagUA"),
        CurrencyInfo(code: "UGX", name: "Ugandan Shilling", region: "Uganda", flagAssetName: "FlagUG"),
        CurrencyInfo(code: "USD", name: "US Dollar", region: "United States", flagAssetName: "FlagUS"),
        CurrencyInfo(code: "UYU", name: "Uruguayan Peso", region: "Uruguay", flagAssetName: "FlagUY"),
        CurrencyInfo(code: "VND", name: "Vietnamese Dong", region: "Vietnam", flagAssetName: "FlagVN"),
        CurrencyInfo(code: "ZAR", name: "South African Rand", region: "South Africa", flagAssetName: "FlagZA"),
        CurrencyInfo(code: "ZMW", name: "Zambian Kwacha", region: "Zambia", flagAssetName: "FlagZM")
    ]

    private static let index: [CurrencyCode: CurrencyInfo] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )

    static func info(for code: CurrencyCode) -> CurrencyInfo? {
        index[code]
    }

    /// 表里有的才认。旧缓存或者手改过的偏好里可能躺着已经下架的代码。
    static func contains(_ code: CurrencyCode) -> Bool {
        index[code] != nil
    }
}
