import XCTest
@testable import PawFolio

final class HoldingSyncCoordinatorTests: XCTestCase {
    func testSyncMergesRemoteWinnerSavesLocallyAndUploadsLocalWinner() async throws {
        let userID = "user-1"
        let localWinner = holding(id: "shared", quantity: 3, updatedAt: 300)
        let remoteLoser = holding(id: "shared", quantity: 1, updatedAt: 200)
        let remoteOnly = holding(id: "remote", quantity: 4, updatedAt: 250)
        let local = MemoryScopedHoldingRepository(
            records: [.account(userID: userID): [localWinner]]
        )
        let cloud = FakeCloudHoldingRepository(records: [userID: [remoteLoser, remoteOnly]])
        let coordinator = HoldingSyncCoordinator(
            authentication: StubAuthentication(session: session(userID: userID)),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        let outcome = try await coordinator.synchronize(guestImportPolicy: .keepSeparate)

        XCTAssertEqual(outcome.state, .synchronized)
        XCTAssertEqual(Set(outcome.holdings.map(\.id)), ["shared", "remote"])
        let saved = await local.records(for: .account(userID: userID))
        XCTAssertEqual(saved, outcome.holdings)
        let uploaded = await cloud.upsertedIDs()
        XCTAssertEqual(uploaded, ["shared"])
        let cloudShared = await cloud.holding(id: "shared", userID: userID)
        XCTAssertEqual(cloudShared?.quantity, 3)
    }

    func testFailedRemoteUploadKeepsMergedLocalStateAndRetriesSafely() async throws {
        let userID = "user-1"
        let localOnly = holding(id: "local", quantity: 2, updatedAt: 300)
        let remoteOnly = holding(id: "remote", quantity: 5, updatedAt: 200)
        let local = MemoryScopedHoldingRepository(
            records: [.account(userID: userID): [localOnly]]
        )
        let cloud = FakeCloudHoldingRepository(
            records: [userID: [remoteOnly]],
            remainingUpsertFailures: 1
        )
        let coordinator = HoldingSyncCoordinator(
            authentication: StubAuthentication(session: session(userID: userID)),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        let first = try await coordinator.synchronize(guestImportPolicy: .keepSeparate)
        XCTAssertEqual(first.state, .pendingRemoteUpload(count: 1))
        let savedAfterFailure = await local.records(for: .account(userID: userID))
        XCTAssertEqual(Set(savedAfterFailure.map(\.id)), ["local", "remote"])
        let missingAfterFailure = await cloud.holding(id: "local", userID: userID)
        XCTAssertNil(missingAfterFailure)

        let retry = try await coordinator.synchronize(guestImportPolicy: .keepSeparate)
        XCTAssertEqual(retry.state, .synchronized)
        let uploadedAfterRetry = await cloud.holding(id: "local", userID: userID)
        XCTAssertEqual(uploadedAfterRetry, localOnly)
    }

    func testGuestHoldingsStaySeparateUnlessCopyIsExplicit() async throws {
        let userID = "user-1"
        let guest = holding(id: "guest", quantity: 1, updatedAt: 100)
        let account = holding(id: "account", quantity: 2, updatedAt: 200)
        let local = MemoryScopedHoldingRepository(records: [
            .guest: [guest],
            .account(userID: userID): [account]
        ])
        let cloud = FakeCloudHoldingRepository()
        let coordinator = HoldingSyncCoordinator(
            authentication: StubAuthentication(session: session(userID: userID)),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        let separate = try await coordinator.synchronize(guestImportPolicy: .keepSeparate)
        XCTAssertEqual(separate.holdings.map(\.id), ["account"])
        XCTAssertEqual(separate.copiedGuestHoldingCount, 0)

        let copied = try await coordinator.synchronize(guestImportPolicy: .copyIntoAccount)
        XCTAssertEqual(Set(copied.holdings.map(\.id)), ["account", "guest"])
        XCTAssertEqual(copied.copiedGuestHoldingCount, 1)
        let guestAfterCopy = await local.records(for: .guest)
        XCTAssertEqual(guestAfterCopy, [guest])
    }

    func testCloudPullFailureDoesNotRewriteAccountFile() async throws {
        let userID = "user-1"
        let account = holding(id: "account", quantity: 2, updatedAt: 200)
        let local = MemoryScopedHoldingRepository(
            records: [.account(userID: userID): [account]]
        )
        let cloud = FakeCloudHoldingRepository(shouldFailFetch: true)
        let coordinator = HoldingSyncCoordinator(
            authentication: StubAuthentication(session: session(userID: userID)),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        do {
            _ = try await coordinator.synchronize(guestImportPolicy: .keepSeparate)
            XCTFail("Expected cloud pull to fail")
        } catch TestSyncError.offline {
            let saved = await local.records(for: .account(userID: userID))
            XCTAssertEqual(saved, [account])
            let saveCount = await local.saveCount()
            XCTAssertEqual(saveCount, 0)
        }
    }

    func testSignedOutAndExpiredSessionsAreRejectedBeforeStorageAccess() async throws {
        let local = MemoryScopedHoldingRepository()
        let cloud = FakeCloudHoldingRepository()
        let signedOut = HoldingSyncCoordinator(
            authentication: StubAuthentication(session: nil),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        do {
            _ = try await signedOut.synchronize(guestImportPolicy: .keepSeparate)
            XCTFail("Expected signed-out sync to fail")
        } catch let error as HoldingSyncCoordinatorError {
            guard case .signedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let expired = HoldingSyncCoordinator(
            authentication: StubAuthentication(
                session: AuthenticatedSession(
                    userID: "user-1",
                    email: nil,
                    provider: .apple,
                    expiresAtMilliseconds: 400
                )
            ),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        do {
            _ = try await expired.synchronize(guestImportPolicy: .keepSeparate)
            XCTFail("Expected expired sync to fail")
        } catch let error as HoldingSyncCoordinatorError {
            guard case .expiredSession = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let loadCount = await local.loadCount()
        XCTAssertEqual(loadCount, 0)
    }

    private func session(userID: String) -> AuthenticatedSession {
        AuthenticatedSession(
            userID: userID,
            email: nil,
            provider: .apple,
            expiresAtMilliseconds: 1_000
        )
    }

    private func holding(id: String, quantity: Double, updatedAt: TimeInterval) -> Holding {
        Holding(
            id: id,
            symbol: "AAPL",
            holdingKind: .market,
            quantity: quantity,
            costPerShare: 100,
            createdAt: 100,
            updatedAt: updatedAt
        )
    }
}

private enum TestSyncError: Error {
    case offline
    case missingSession
}

private actor StubAuthentication: AuthenticationSessionServing {
    private var session: AuthenticatedSession?

    init(session: AuthenticatedSession?) {
        self.session = session
    }

    func currentSession() async throws -> AuthenticatedSession? {
        session
    }

    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession {
        guard let session else { throw TestSyncError.missingSession }
        return session
    }

    func signOut() async throws {
        session = nil
    }
}

private actor MemoryScopedHoldingRepository: ScopedHoldingRepository {
    private var storage: [HoldingStorageScope: [Holding]]
    private var loadCalls = 0
    private var saveCalls = 0

    init(records: [HoldingStorageScope: [Holding]] = [:]) {
        storage = records
    }

    func load(for scope: HoldingStorageScope) async throws -> [Holding] {
        loadCalls += 1
        return storage[scope] ?? []
    }

    func save(_ holdings: [Holding], for scope: HoldingStorageScope) async throws {
        saveCalls += 1
        storage[scope] = holdings
    }

    func records(for scope: HoldingStorageScope) -> [Holding] {
        storage[scope] ?? []
    }

    func loadCount() -> Int { loadCalls }
    func saveCount() -> Int { saveCalls }
}

private actor FakeCloudHoldingRepository: CloudHoldingRepository {
    private var storage: [String: [Holding]]
    private var uploadedIDs: [String] = []
    private var remainingUpsertFailures: Int
    private let shouldFailFetch: Bool

    init(
        records: [String: [Holding]] = [:],
        remainingUpsertFailures: Int = 0,
        shouldFailFetch: Bool = false
    ) {
        storage = records
        self.remainingUpsertFailures = remainingUpsertFailures
        self.shouldFailFetch = shouldFailFetch
    }

    func fetchAll(for userID: String) async throws -> [Holding] {
        guard !shouldFailFetch else { throw TestSyncError.offline }
        return storage[userID] ?? []
    }

    func upsert(_ holdings: [Holding], for userID: String) async throws {
        if remainingUpsertFailures > 0 {
            remainingUpsertFailures -= 1
            throw TestSyncError.offline
        }

        var records = Dictionary(uniqueKeysWithValues: (storage[userID] ?? []).map { ($0.id, $0) })
        for holding in holdings {
            records[holding.id] = holding
            uploadedIDs.append(holding.id)
        }
        storage[userID] = records.values.sorted { $0.id < $1.id }
    }

    func holding(id: String, userID: String) -> Holding? {
        storage[userID]?.first { $0.id == id }
    }

    func upsertedIDs() -> [String] {
        uploadedIDs
    }
}
