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

        var rates: [CurrencyCode: Double] = [.usd: 1]
        for code in CurrencyCode.allCases {
            guard let value = payload.rates[code.rawValue], value.isFinite, value > 0 else {
                throw ExchangeRateClientError.invalidResponse
            }
            rates[code] = value
        }

        let fetchedAt = payload.timeLastUpdateUnix.map(Date.init(timeIntervalSince1970:)) ?? Date()
        return ExchangeRateSnapshot(base: .usd, ratesPerUSD: rates, fetchedAt: fetchedAt)
    }
}

