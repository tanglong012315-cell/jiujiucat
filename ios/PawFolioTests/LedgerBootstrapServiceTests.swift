import XCTest
@testable import PawFolio

final class LedgerBootstrapServiceTests: XCTestCase {
    func testBootstrapMigratesLegacyHoldingsExactlyOnce() async throws {
        let repository = InMemoryLedgerRepository()
        let service = LedgerBootstrapService(repository: repository)
        let holding = Holding(
            id: "btc",
            symbol: "BTC",
            assetType: .cryptocurrency,
            holdingKind: .market,
            quantity: 1,
            createdAt: 1
        )
        let date = Date(timeIntervalSince1970: 100)

        let first = try await service.bootstrap(scope: .guest, legacyHoldings: [holding], openingAt: date)
        let second = try await service.bootstrap(scope: .guest, legacyHoldings: [holding], openingAt: date)
        let saveCount = await repository.saveCount

        XCTAssertEqual(first.entries.count, 1)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.legacyMigrationVersion, HoldingLedgerMigration.migrationVersion)
        XCTAssertEqual(saveCount, 1)
    }
}

private actor InMemoryLedgerRepository: ScopedLedgerRepository {
    private var snapshot = LedgerStoreSnapshot()
    private(set) var saveCount = 0

    func load(for scope: HoldingStorageScope) async throws -> LedgerStoreSnapshot {
        snapshot
    }

    func save(_ snapshot: LedgerStoreSnapshot, for scope: HoldingStorageScope) async throws {
        self.snapshot = snapshot
        saveCount += 1
    }
}
