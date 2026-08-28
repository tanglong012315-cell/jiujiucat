import XCTest
@testable import PawFolio

final class HoldingRecordMutationTests: XCTestCase {
    func testInterestEntriesUseHistoricalPrincipalAndSkipDates() throws {
        var holding = interestHolding(mode: .simple)
        holding.principal = 15_000
        holding.principalAdjustments = [
            PrincipalAdjustment(
                id: "p_add",
                type: .add,
                amount: 5_000,
                date: "2026-08-21",
                createdAt: milliseconds("2026-08-21T02:00:00Z")
            )
        ]
        holding.interestSkips = ["2026-08-22"]

        let entries = HoldingValuation.interestRecordEntries(
            for: holding,
            at: milliseconds("2026-08-23T08:00:00Z")
        )

        XCTAssertEqual(entries.map(\.date), ["2026-08-21", "2026-08-23"])
        XCTAssertEqual(entries[0].principal, 10_000)
        XCTAssertEqual(entries[0].amount, 10, accuracy: 0.000_001)
        XCTAssertEqual(entries[1].principal, 15_000)
        XCTAssertEqual(entries[1].amount, 15, accuracy: 0.000_001)
    }

    func testCompoundInterestEntriesSumToAccruedInterest() {
        let holding = interestHolding(mode: .compound)
        let at = milliseconds("2026-08-23T08:00:00Z")
        let entries = HoldingValuation.interestRecordEntries(for: holding, at: at)

        XCTAssertEqual(entries.map(\.amount).reduce(0, +), 30.03001, accuracy: 0.000_001)
        XCTAssertEqual(
            entries.map(\.amount).reduce(0, +),
            HoldingValuation.accruedInterest(for: holding, at: at),
            accuracy: 0.000_001
        )
    }

    func testSkipAndRestoreInterestSettlement() throws {
        let holding = interestHolding(mode: .simple)
        let at = milliseconds("2026-08-23T12:00:00Z")

        let skipped = try HoldingRecordMutation.skippingInterestSettlement(
            holdingID: holding.id,
            date: "2026-08-22",
            occurredAt: at,
            in: [holding]
        )
        XCTAssertEqual(skipped[0].interestSkips, ["2026-08-22"])
        XCTAssertEqual(HoldingValuation.accruedInterest(for: skipped[0], at: at), 20, accuracy: 0.000_001)

        let restored = try HoldingRecordMutation.restoringInterestSettlement(
            holdingID: holding.id,
            date: "2026-08-22",
            occurredAt: at + 1,
            in: skipped
        )
        XCTAssertTrue(restored[0].interestSkips.isEmpty)
        XCTAssertEqual(HoldingValuation.accruedInterest(for: restored[0], at: at), 30, accuracy: 0.000_001)
    }

    func testCannotSkipFutureInterestSettlement() {
        let holding = interestHolding(mode: .simple)
        XCTAssertThrowsError(
            try HoldingRecordMutation.skippingInterestSettlement(
                holdingID: holding.id,
                date: "2026-08-24",
                occurredAt: milliseconds("2026-08-23T12:00:00Z"),
                in: [holding]
            )
        ) { error in
            XCTAssertEqual(error as? HoldingRecordError, .interestRecordNotFound)
        }
    }

    func testCreateDividendRecordFreezesCurrentQuantityAndUpdatesCurrentFields() throws {
        let result = try HoldingRecordMutation.upsertingDividendRecord(
            dividendRequest(),
            in: [dividendHolding()]
        )

        let record = try XCTUnwrap(result[0].dividendRecords.first)
        XCTAssertEqual(record.quantity, 12)
        XCTAssertEqual(record.amount, 3)
        XCTAssertEqual(result[0].dividendRecordId, record.id)
        XCTAssertEqual(result[0].dividendPerShare, 0.25)
        XCTAssertEqual(result[0].dividendExDate, "2026-09-01")
    }

    func testEditDividendRecordPreservesFrozenQuantity() throws {
        var holding = dividendHolding()
        holding.quantity = 20
        holding.dividendRecords = [dividendRecord(id: "record", quantity: 12)]
        holding.dividendRecordId = "record"

        let result = try HoldingRecordMutation.upsertingDividendRecord(
            DividendRecordRequest(
                holdingID: holding.id,
                recordID: "record",
                perShare: 0.5,
                frequency: .monthly,
                exDate: "2026-09-02",
                payDate: "2026-09-10",
                occurredAt: now
            ),
            in: [holding]
        )

        XCTAssertEqual(result[0].dividendRecords[0].quantity, 12)
        XCTAssertEqual(result[0].dividendRecords[0].amount, 6)
        XCTAssertEqual(result[0].dividendPerShare, 0.5)
    }

    func testDeletingCurrentDividendRecordClearsCurrentFields() throws {
        var holding = dividendHolding()
        holding.dividendRecords = [dividendRecord(id: "record", quantity: 12)]
        holding.dividendRecordId = "record"
        holding.dividendPerShare = 0.25
        holding.dividendFrequency = .quarterly
        holding.dividendExDate = "2026-09-01"
        holding.dividendPayDate = "2026-09-10"

        let result = try HoldingRecordMutation.deletingDividendRecord(
            holdingID: holding.id,
            recordID: "record",
            occurredAt: now,
            in: [holding]
        )

        XCTAssertTrue(result[0].dividendRecords.isEmpty)
        XCTAssertNil(result[0].dividendRecordId)
        XCTAssertNil(result[0].dividendPerShare)
        XCTAssertNil(result[0].dividendFrequency)
        XCTAssertNil(result[0].dividendExDate)
        XCTAssertNil(result[0].dividendPayDate)
    }

    private let now = ISO8601DateFormatter()
        .date(from: "2026-08-28T08:00:00Z")!
        .timeIntervalSince1970 * 1_000

    private func interestHolding(mode: InterestMode) -> Holding {
        Holding(
            id: "interest",
            symbol: "USDT",
            holdingKind: .interest,
            principal: 10_000,
            annualRate: 36.5,
            interestMode: mode,
            interestStartDate: "2026-08-20",
            createdAt: 1
        )
    }

    private func dividendHolding() -> Holding {
        Holding(
            id: "dividend",
            symbol: "AAPL",
            assetType: .equity,
            holdingKind: .dividend,
            quantity: 12,
            costPerShare: 100,
            createdAt: 1
        )
    }

    private func dividendRequest() -> DividendRecordRequest {
        DividendRecordRequest(
            holdingID: "dividend",
            recordID: nil,
            perShare: 0.25,
            frequency: .quarterly,
            exDate: "2026-09-01",
            payDate: "2026-09-10",
            occurredAt: now
        )
    }

    private func dividendRecord(id: String, quantity: Double) -> DividendRecord {
        DividendRecord(
            id: id,
            perShare: 0.25,
            quantity: quantity,
            amount: quantity * 0.25,
            frequency: .quarterly,
            exDate: "2026-09-01",
            payDate: "2026-09-10",
            createdAt: 1
        )
    }

    private func milliseconds(_ iso8601: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970 * 1_000
    }
}
