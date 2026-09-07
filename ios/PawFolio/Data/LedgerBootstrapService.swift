import Foundation

/// 将 schema-v2 持仓一次性落成 schema-v3 期初账本。迁移标记和结果同文件原子保存，
/// 因此重复启动不会重复增加资产。
struct LedgerBootstrapService: Sendable {
    private let repository: any ScopedLedgerRepository

    init(repository: any ScopedLedgerRepository) {
        self.repository = repository
    }

    func bootstrap(
        scope: HoldingStorageScope,
        legacyHoldings: [Holding],
        openingAt: Date
    ) async throws -> LedgerStoreSnapshot {
        var snapshot = try await repository.load(for: scope)
        if snapshot.legacyMigrationVersion ?? 0 >= HoldingLedgerMigration.migrationVersion {
            return snapshot
        }

        let migration = HoldingLedgerMigration.migrate(legacyHoldings, openingAt: openingAt)
        guard migration.skippedHoldingIDs.isEmpty else {
            throw LedgerBootstrapError.incompleteMigration(migration.skippedHoldingIDs)
        }
        snapshot.entries.append(contentsOf: migration.entries)
        snapshot.earnProducts.append(contentsOf: migration.earnProducts)
        snapshot.legacyMigrationVersion = HoldingLedgerMigration.migrationVersion
        try await repository.save(snapshot, for: scope)
        return snapshot
    }
}

enum LedgerBootstrapError: LocalizedError, Equatable {
    case incompleteMigration([String])

    var errorDescription: String? {
        switch self {
        case let .incompleteMigration(ids):
            "Unable to migrate \(ids.count) existing position\(ids.count == 1 ? "" : "s"). Your original data was not changed."
        }
    }
}
