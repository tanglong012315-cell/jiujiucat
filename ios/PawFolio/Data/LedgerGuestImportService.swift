import Foundation

protocol LedgerGuestImporting: Sendable {
    func guestAssetCount(
        guestHoldings: [Holding],
        openingAt: Date
    ) async throws -> Int

    func copyGuestLedgerIntoAccount(
        userID: String,
        guestHoldings: [Holding],
        accountHoldings: [Holding],
        openingAt: Date
    ) async throws
}

struct LedgerGuestImportService: LedgerGuestImporting, Sendable {
    let repository: any ScopedLedgerRepository

    func guestAssetCount(
        guestHoldings: [Holding],
        openingAt: Date
    ) async throws -> Int {
        let guest = try await LedgerBootstrapService(repository: repository).bootstrap(
            scope: .guest,
            legacyHoldings: guestHoldings,
            openingAt: openingAt
        )
        let projection = try LedgerProjection(entries: guest.entries)
        let activeBalanceCount = projection.balances.reduce(into: 0) { count, item in
            if item.key.account.isUserControlled,
               item.value > LedgerEntry.balanceTolerance {
                count += 1
            }
        }
        // A fully spent account can still contain transaction history the user
        // expects to keep. Surface one import item instead of silently leaving
        // that history behind just because every current balance is zero.
        if activeBalanceCount == 0,
           !guest.entries.isEmpty || !guest.earnProducts.isEmpty {
            return 1
        }
        return activeBalanceCount
    }

    func copyGuestLedgerIntoAccount(
        userID: String,
        guestHoldings: [Holding],
        accountHoldings: [Holding],
        openingAt: Date
    ) async throws {
        let accountScope = HoldingStorageScope.account(userID: userID)
        let guest = try await LedgerBootstrapService(repository: repository).bootstrap(
            scope: .guest,
            legacyHoldings: guestHoldings,
            openingAt: openingAt
        )
        var account = try await LedgerBootstrapService(repository: repository).bootstrap(
            scope: accountScope,
            legacyHoldings: accountHoldings,
            openingAt: openingAt
        )

        for entry in guest.entries {
            if let existing = account.entries.first(where: { $0.id == entry.id }) {
                guard existing == entry else { throw LedgerGuestImportError.conflictingEntry(entry.id) }
            } else {
                account.entries.append(entry)
            }
        }
        for product in guest.earnProducts {
            if let existing = account.earnProducts.first(where: { $0.id == product.id }) {
                guard existing == product else { throw LedgerGuestImportError.conflictingProduct(product.id) }
            } else {
                account.earnProducts.append(product)
            }
        }
        account.legacyMigrationVersion = max(
            account.legacyMigrationVersion ?? 0,
            guest.legacyMigrationVersion ?? 0
        )
        try await repository.save(account, for: accountScope)
    }
}

enum LedgerGuestImportError: LocalizedError, Equatable {
    case conflictingEntry(String)
    case conflictingProduct(String)

    var errorDescription: String? {
        switch self {
        case .conflictingEntry:
            "Guest transactions conflict with this account. Nothing was copied."
        case .conflictingProduct:
            "Guest Earn products conflict with this account. Nothing was copied."
        }
    }
}
