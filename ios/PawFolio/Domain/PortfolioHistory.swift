import Foundation

enum PortfolioHistoryRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    /// `47:1090` 于 2026-09-02 改成缩写，并换用 Section 而不是 Segment Control。
    var title: String {
        switch self {
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .year: "1Y"
        }
    }

    var spanMilliseconds: TimeInterval {
        switch self {
        case .day: HoldingValuation.dayMilliseconds
        case .week: 7 * HoldingValuation.dayMilliseconds
        case .month: 30 * HoldingValuation.dayMilliseconds
        case .year: 365 * HoldingValuation.dayMilliseconds
        }
    }

    var sampleCount: Int {
        switch self {
        case .day: 48
        case .week: 169
        case .month: 180
        case .year: 183
        }
    }

    var prefersOneYearHistory: Bool {
        self == .month || self == .year
    }

    func timeline(endingAt timestampMilliseconds: TimeInterval) -> [TimeInterval] {
        let denominator = Double(sampleCount - 1)
        return (0..<sampleCount).map { index in
            timestampMilliseconds
                - spanMilliseconds * Double(sampleCount - 1 - index) / denominator
        }
    }
}

struct PortfolioHistoryPoint: Equatable, Identifiable, Sendable {
    let timestampMilliseconds: TimeInterval
    let value: Double

    var id: TimeInterval { timestampMilliseconds }
}
