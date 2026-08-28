import XCTest
@testable import PawFolio

final class HoldingMergeTests: XCTestCase {
    func testLocalOnlyRecordIsKeptAndScheduledForRemoteUpsert() throws {
        let local = holding(id: "local", quantity: 1, createdAt: 100, updatedAt: 120)

        let result = HoldingMerge.reconcile(local: [local], remote: [])

        XCTAssertEqual(result.holdings, [local])
        XCTAssertFalse(result.requiresLocalSave)
        XCTAssertEqual(result.remoteUpserts, [local])
    }

    func testRemoteOnlyRecordIsSavedLocallyWithoutRedundantUpload() throws {
        let remote = holding(id: "remote", quantity: 2, createdAt: 100, updatedAt: 120)

        let result = HoldingMerge.reconcile(local: [], remote: [remote])

        XCTAssertEqual(result.holdings, [remote])
        XCTAssertEqual(result.localChangedIDs, ["remote"])
        XCTAssertTrue(result.remoteUpserts.isEmpty)
    }

    func testNewerLocalVersionWins() throws {
        let local = holding(id: "same", quantity: 3, createdAt: 100, updatedAt: 300)
        let remote = holding(id: "same", quantity: 1, createdAt: 100, updatedAt: 200)

        let result = HoldingMerge.reconcile(local: [local], remote: [remote])

        XCTAssertEqual(result.holdings, [local])
        XCTAssertEqual(result.remoteUpserts, [local])
        XCTAssertFalse(result.requiresLocalSave)
    }

    func testNewerRemoteVersionWins() throws {
        let local = holding(id: "same", quantity: 1, createdAt: 100, updatedAt: 200)
        let remote = holding(id: "same", quantity: 3, createdAt: 100, updatedAt: 300)

        let result = HoldingMerge.reconcile(local: [local], remote: [remote])

        XCTAssertEqual(result.holdings, [remote])
        XCTAssertEqual(result.localChangedIDs, ["same"])
        XCTAssertTrue(result.remoteUpserts.isEmpty)
    }

    func testTombstoneWinsAnExactTimestampTie() throws {
        let active = holding(id: "same", quantity: 1, createdAt: 100, updatedAt: 300)
        let tombstone = holding(
            id: "same",
            quantity: 1,
            createdAt: 100,
            updatedAt: 300,
            deletedAt: 300
        )

        let result = HoldingMerge.reconcile(local: [active], remote: [tombstone])

        XCTAssertEqual(result.holdings, [tombstone])
        XCTAssertTrue(result.holdings[0].isDeleted)
        XCTAssertEqual(result.localChangedIDs, ["same"])
        XCTAssertTrue(result.remoteUpserts.isEmpty)
    }

    func testDeletedAtParticipatesWhenUpdatedAtIsMissing() throws {
        let staleActive = holding(id: "same", quantity: 1, createdAt: 200, updatedAt: nil)
        let tombstone = holding(
            id: "same",
            quantity: 1,
            createdAt: 100,
            updatedAt: nil,
            deletedAt: 300
        )

        let result = HoldingMerge.reconcile(local: [staleActive], remote: [tombstone])

        XCTAssertTrue(result.holdings[0].isDeleted)
        XCTAssertEqual(HoldingMerge.conflictTimestamp(for: tombstone), 300)
    }

    func testLegacyRecordWithoutUpdatedAtFallsBackToCreatedAt() throws {
        let newerLegacy = holding(id: "same", quantity: 4, createdAt: 400, updatedAt: nil)
        let olderRemote = holding(id: "same", quantity: 2, createdAt: 200, updatedAt: 300)

        let result = HoldingMerge.reconcile(local: [newerLegacy], remote: [olderRemote])

        XCTAssertEqual(result.holdings[0].quantity, 4)
        XCTAssertEqual(result.remoteUpserts[0].quantity, 4)
    }

    func testZeroUpdatedAtAlsoFallsBackToCreatedAtLikeWeb() throws {
        let local = holding(id: "same", quantity: 4, createdAt: 400, updatedAt: 0)
        let remote = holding(id: "same", quantity: 2, createdAt: 200, updatedAt: 300)

        let result = HoldingMerge.reconcile(local: [local], remote: [remote])

        XCTAssertEqual(result.holdings[0].quantity, 4)
    }

    func testLegacyWinnerIsUpgradedBeforePersistenceAndUpload() throws {
        let legacy = holding(
            schemaVersion: 1,
            id: "legacy",
            quantity: 1,
            createdAt: 100,
            updatedAt: nil
        )

        let result = HoldingMerge.reconcile(local: [legacy], remote: [])

        XCTAssertEqual(result.holdings[0].schemaVersion, Holding.currentSchemaVersion)
        XCTAssertEqual(result.localChangedIDs, ["legacy"])
        XCTAssertEqual(result.remoteUpserts[0].schemaVersion, Holding.currentSchemaVersion)
    }

    func testAuthenticatedSessionExpirationBoundary() {
        let session = AuthenticatedSession(
            userID: "user-1",
            email: nil,
            provider: .apple,
            expiresAtMilliseconds: 500
        )

        XCTAssertFalse(session.isExpired(at: 499))
        XCTAssertTrue(session.isExpired(at: 500))
    }

    private func holding(
        schemaVersion: Int = Holding.currentSchemaVersion,
        id: String,
        quantity: Double,
        createdAt: TimeInterval,
        updatedAt: TimeInterval?,
        deletedAt: TimeInterval? = nil
    ) -> Holding {
        Holding(
            schemaVersion: schemaVersion,
            id: id,
            symbol: "AAPL",
            holdingKind: .market,
            quantity: quantity,
            costPerShare: 100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
