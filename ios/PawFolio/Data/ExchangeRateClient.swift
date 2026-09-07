import Foundation

enum ExchangeRateClientError: LocalizedError {
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "汇率服务返回了无法识别的数据。"
        case .unavailable:
            "暂时无法获取最新汇率。"
        }
    }
}

protocol ExchangeRateServing: Sendable {
    func latestRates() async throws -> ExchangeRateSnapshot
}

struct LiveExchangeRateClient: ExchangeRateServing {
    private struct Response: Decodable {
        let result: String?
        let timeLastUpdateUnix: TimeInterval?
        let rates: [String: Double]

        enum CodingKeys: String, CodingKey {
            case result
            case timeLastUpdateUnix = "time_last_update_unix"
            case rates
        }
    }

    private let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    func latestRates() async throws -> ExchangeRateSnapshot {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw ExchangeRateClientError.unavailable
        }

        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard payload.result != "error" else {
            throw ExchangeRateClientError.unavailable
        }

        // 只留币种表里有的，别把接口那一百六十来种全存进缓存。
        //
        // 单个币缺价**不再**整体报错：币种表放开到七十来种之后，任何一个冷门币在
        // 上游临时缺数据都会让整页汇率消失。缺的那个由界面单独标成不可用。
        var rates: [CurrencyCode: Double] = [:]
        for info in CurrencyCatalog.all {
            guard let value = payload.rates[info.code.rawValue], value.isFinite, value > 0 else {
                continue
            }
            rates[info.code] = value
        }
        rates[.usd] = 1

        // USD 是基准，其余全折算自它。一个都没对上说明拿到的不是汇率表。
        guard rates.count > 1 else {
            throw ExchangeRateClientError.invalidResponse
        }

        let fetchedAt = payload.timeLastUpdateUnix.map(Date.init(timeIntervalSince1970:)) ?? Date()
        return ExchangeRateSnapshot(base: .usd, ratesPerUSD: rates, fetchedAt: fetchedAt)
    }
}

