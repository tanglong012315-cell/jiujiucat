import XCTest
@testable import PawFolio

final class LedgerRepositoryTests: XCTestCase {
    func testGuestAndAccountLedgersAreIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScopedLocalLedgerRepository(baseDirectoryURL: directory)
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let entry = try LedgerEntry.deposit(
            asset: usd,
            quantity: 10,
            occurredAt: Date(timeIntervalSince1970: 123),
            id: "deposit"
        )
        let snapshot = LedgerStoreSnapshot(
            legacyMigrationVersion: HoldingLedgerMigration.migrationVersion,
            entries: [entry]
        )

        try await repository.save(snapshot, for: .guest)

        let guest = try await repository.load(for: .guest)
        let account = try await repository.load(for: .account(userID: "user-1"))
        XCTAssertEqual(guest, snapshot)
        XCTAssertTrue(account.entries.isEmpty)
    }

    func testRepositoryRefusesSnapshotThatOverdraws() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScopedLocalLedgerRepository(baseDirectoryURL: directory)
        let expense = try LedgerEntry.expense(
            asset: LedgerAsset(code: "USD", kind: .fiat),
            quantity: 10,
            from: "bank",
            occurredAt: Date()
        )

        do {
            try await repository.save(LedgerStoreSnapshot(entries: [expense]), for: .guest)
            XCTFail("Expected insufficient balance")
        } catch let error as LedgerError {
            guard case .insufficientBalance = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testGuestLedgerImportMergesByImmutableIDAndIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerGuestImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScopedLocalLedgerRepository(baseDirectoryURL: directory)
        let service = LedgerGuestImportService(repository: repository)
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let guestEntry = try LedgerEntry.deposit(
            asset: usd, quantity: 10, occurredAt: Date(timeIntervalSince1970: 1), id: "guest"
        )
        let accountEntry = try LedgerEntry.deposit(
            asset: usd, quantity: 20, occurredAt: Date(timeIntervalSince1970: 2), id: "account"
        )
        try await repository.save(
            LedgerStoreSnapshot(legacyMigrationVersion: 1, entries: [guestEntry]),
            for: .guest
        )
        try await repository.save(
            LedgerStoreSnapshot(legacyMigrationVersion: 1, entries: [accountEntry]),
            for: .account(userID: "user-1")
        )

        let guestAssetCount = try await service.guestAssetCount(guestHoldings: [], openingAt: Date())
        XCTAssertEqual(guestAssetCount, 1)
        try await service.copyGuestLedgerIntoAccount(
            userID: "user-1", guestHoldings: [], accountHoldings: [], openingAt: Date()
        )
        try await service.copyGuestLedgerIntoAccount(
            userID: "user-1", guestHoldings: [], accountHoldings: [], openingAt: Date()
        )

        let guest = try await repository.load(for: .guest)
        let account = try await repository.load(for: .account(userID: "user-1"))
        XCTAssertEqual(guest.entries, [guestEntry])
        XCTAssertEqual(Set(account.entries.map(\.id)), ["guest", "account"])
    }

    func testGuestLedgerImportRejectsConflictingIDsWithoutOverwritingAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerGuestImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScopedLocalLedgerRepository(baseDirectoryURL: directory)
        let service = LedgerGuestImportService(repository: repository)
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let guestEntry = try LedgerEntry.deposit(
            asset: usd, quantity: 10, occurredAt: Date(timeIntervalSince1970: 1), id: "same"
        )
        let accountEntry = try LedgerEntry.deposit(
            asset: usd, quantity: 20, occurredAt: Date(timeIntervalSince1970: 2), id: "same"
        )
        let original = LedgerStoreSnapshot(legacyMigrationVersion: 1, entries: [accountEntry])
        try await repository.save(
            LedgerStoreSnapshot(legacyMigrationVersion: 1, entries: [guestEntry]), for: .guest
        )
        try await repository.save(original, for: .account(userID: "user-1"))

        do {
            try await service.copyGuestLedgerIntoAccount(
                userID: "user-1", guestHoldings: [], accountHoldings: [], openingAt: Date()
            )
            XCTFail("Expected a conflict")
        } catch {
            XCTAssertEqual(error as? LedgerGuestImportError, .conflictingEntry("same"))
        }

        let unchanged = try await repository.load(for: .account(userID: "user-1"))
        XCTAssertEqual(unchanged, original)
    }

    func testSpentGuestLedgerStillRequestsImportForItsHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerGuestImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ScopedLocalLedgerRepository(baseDirectoryURL: directory)
        let service = LedgerGuestImportService(repository: repository)
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let deposit = try LedgerEntry.deposit(
            asset: usd, quantity: 10, occurredAt: Date(timeIntervalSince1970: 1), id: "deposit"
        )
        let expense = try LedgerEntry.expense(
            asset: usd, quantity: 10, from: "exchange",
            occurredAt: Date(timeIntervalSince1970: 2), id: "expense"
        )
        try await repository.save(
            LedgerStoreSnapshot(legacyMigrationVersion: 1, entries: [deposit, expense]),
            for: .guest
        )

        let count = try await service.guestAssetCount(guestHoldings: [], openingAt: Date())

        XCTAssertEqual(count, 1)
    }
}
