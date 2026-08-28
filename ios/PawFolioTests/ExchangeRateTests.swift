import XCTest
@testable import PawFolio

final class ExchangeRateTests: XCTestCase {
    func testCrossRateConversionUsesUSDBaseRates() throws {
        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 7.2, .thb: 36, .myr: 4.5],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try XCTUnwrap(snapshot.converted(1_000, from: .cny, to: .thb))

        XCTAssertEqual(result, 5_000, accuracy: 0.000_001)
    }

    func testInvalidRateDoesNotProduceAConversion() {
        let snapshot = ExchangeRateSnapshot(
            base: .usd,
            ratesPerUSD: [.usd: 1, .cny: 0, .thb: 36],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(snapshot.converted(100, from: .cny, to: .thb))
    }
}

