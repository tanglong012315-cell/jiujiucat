import Foundation

/// ISO 4217 货币代码。
///
/// V1.2.0 之前这里是四个 case 的枚举。汇率页开放到七十来种法币之后，枚举既写不下
/// 也挡不住接口回来的新代码，所以改成包一层 `String` 的值类型：**能表示任何代码**，
/// 至于哪些代码是产品支持的，交给 `CurrencyCatalog` 决定。
struct CurrencyCode: RawRepresentable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        // 接口和缓存里都可能是小写，统一成大写才能当字典键用。
        self.rawValue = rawValue.uppercased()
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var id: String { rawValue }

    static let cny = CurrencyCode("CNY")
    static let usd = CurrencyCode("USD")
    static let thb = CurrencyCode("THB")
    static let myr = CurrencyCode("MYR")
}

extension CurrencyCode: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// 编码成裸字符串而不是 `{"rawValue": "USD"}`。
extension CurrencyCode: Codable {
    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 让 `[CurrencyCode: Double]` 编码成 JSON 对象。没有这层的话 Swift 会把它拍平成
/// 键值交替的数组，缓存文件既难读也难在别处复用。
extension CurrencyCode: CodingKeyRepresentable {
    var codingKey: any CodingKey {
        StringCodingKey(stringValue: rawValue)
    }

    init?<Key: CodingKey>(codingKey: Key) {
        self.init(rawValue: codingKey.stringValue)
    }

    private struct StringCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}

extension CurrencyCode {
    /// 货币全名。表里没有就退回代码本身，界面上不至于空一块。
    var displayName: String {
        CurrencyCatalog.info(for: self)?.name ?? rawValue
    }

    func localizedDisplayName(locale: Locale) -> String {
        CurrencyCatalog.info(for: self)?.localizedName(locale: locale) ?? rawValue
    }

    var regionName: String {
        CurrencyCatalog.info(for: self)?.region ?? rawValue
    }

    /// 宿主资源目录里的圆形国旗。
    var flagAssetName: String {
        CurrencyCatalog.info(for: self)?.flagAssetName ?? CurrencyCatalog.unknownFlagAssetName
    }
}

struct ExchangeRateSnapshot: Codable, Equatable, Sendable {
    let base: CurrencyCode
    let ratesPerUSD: [CurrencyCode: Double]
    let fetchedAt: Date

    func converted(_ amount: Double, from source: CurrencyCode, to target: CurrencyCode) -> Double? {
        guard amount.isFinite,
              amount >= 0,
              let sourceRate = ratesPerUSD[source],
              let targetRate = ratesPerUSD[target],
              sourceRate.isFinite,
              targetRate.isFinite,
              sourceRate > 0,
              targetRate > 0 else {
            return nil
        }

        return amount / sourceRate * targetRate
    }

    /// 这一版快照里有没有这个币的价。界面据此决定显示数字还是「Rate unavailable」。
    func hasRate(for code: CurrencyCode) -> Bool {
        guard let rate = ratesPerUSD[code] else { return false }
        return rate.isFinite && rate > 0
    }
}
