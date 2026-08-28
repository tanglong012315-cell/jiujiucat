import Foundation

enum CurrencyCode: String, CaseIterable, Codable, Identifiable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case thb = "THB"
    case myr = "MYR"

    var id: Self { self }

    var flag: String {
        switch self {
        case .cny: "🇨🇳"
        case .usd: "🇺🇸"
        case .thb: "🇹🇭"
        case .myr: "🇲🇾"
        }
    }

    var displayName: String {
        switch self {
        case .cny: "人民币"
        case .usd: "美元"
        case .thb: "泰铢"
        case .myr: "马来西亚令吉"
        }
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
}

