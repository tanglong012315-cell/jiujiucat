import XCTest
@testable import PawFolio

final class ProfileSyncCoordinatorTests: XCTestCase {
    func testRemoteWinnerIsSavedLocallyWithoutUpload() async throws {
        let userID = "user-1"
        let localProfile = profile(name: "Local", avatar: .faceHappy, updatedAt: 100)
        let remoteProfile = profile(name: "Remote", avatar: .catPuffy, updatedAt: 200)
        let local = ProfileMemoryStore(records: [userID: localProfile])
        let cloud = ProfileCloudFake(records: [userID: remoteProfile])
        let coordinator = makeCoordinator(userID: userID, local: local, cloud: cloud)

        let outcome = try await coordinator.synchronize()

        XCTAssertEqual(outcome, ProfileSyncOutcome(
            userID: userID,
            profile: remoteProfile,
            state: .synchronized
        ))
        let saved = try await local.profile(for: userID)
        XCTAssertEqual(saved, remoteProfile)
        let uploadCount = await cloud.upsertCount()
        XCTAssertEqual(uploadCount, 0)
    }

    func testLocalWinnerIsUploadedWithoutRedundantLocalSave() async throws {
        let userID = "user-1"
        let localProfile = profile(name: "Local", avatar: .catJiujiu, updatedAt: 300)
        let remoteProfile = profile(name: "Remote", avatar: .faceCute, updatedAt: 200)
        let local = ProfileMemoryStore(records: [userID: localProfile])
        let cloud = ProfileCloudFake(records: [userID: remoteProfile])
        let coordinator = makeCoordinator(userID: userID, local: local, cloud: cloud)

        let outcome = try await coordinator.synchronize()

        XCTAssertEqual(outcome.state, .synchronized)
        XCTAssertEqual(outcome.profile, localProfile)
        let remote = try await cloud.fetch(for: userID)
        XCTAssertEqual(remote, localProfile)
        let saveCount = await local.saveCount()
        XCTAssertEqual(saveCount, 0)
    }

    func testUneditedMigratedLocalProfileDoesNotCreateMissingRemoteRow() async throws {
        let userID = "user-1"
        let localProfile = profile(name: "Legacy", avatar: .faceLove, updatedAt: 0)
        let local = ProfileMemoryStore(records: [userID: localProfile])
        let cloud = ProfileCloudFake()
        let coordinator = makeCoordinator(userID: userID, local: local, cloud: cloud)

        let outcome = try await coordinator.synchronize()

        XCTAssertEqual(outcome.state, .synchronized)
        XCTAssertEqual(outcome.profile, localProfile)
        let uploadCount = await cloud.upsertCount()
        XCTAssertEqual(uploadCount, 0)
    }

    func testFailedUploadReturnsPendingAndRetryUploadsSameLocalWinner() async throws {
        let userID = "user-1"
        let localProfile = profile(name: "Local", avatar: .catBobo, updatedAt: 300)
        let local = ProfileMemoryStore(records: [userID: localProfile])
        let cloud = ProfileCloudFake(remainingUpsertFailures: 1)
        let coordinator = makeCoordinator(userID: userID, local: local, cloud: cloud)

        let first = try await coordinator.synchronize()
        XCTAssertEqual(first.state, .pendingRemoteUpload)
        let remoteAfterFailure = try await cloud.fetch(for: userID)
        XCTAssertNil(remoteAfterFailure)

        let retry = try await coordinator.synchronize()
        XCTAssertEqual(retry.state, .synchronized)
        let remoteAfterRetry = try await cloud.fetch(for: userID)
        XCTAssertEqual(remoteAfterRetry, localProfile)
    }

    func testPullFailureDoesNotRewriteLocalProfile() async throws {
        let userID = "user-1"
        let localProfile = profile(name: "Local", avatar: .faceThinking, updatedAt: 100)
        let local = ProfileMemoryStore(records: [userID: localProfile])
        let cloud = ProfileCloudFake(shouldFailFetch: true)
        let coordinator = makeCoordinator(userID: userID, local: local, cloud: cloud)

        do {
            _ = try await coordinator.synchronize()
            XCTFail("Expected profile pull to fail")
        } catch ProfileTestError.offline {
            let saved = try await local.profile(for: userID)
            XCTAssertEqual(saved, localProfile)
            let saveCount = await local.saveCount()
            XCTAssertEqual(saveCount, 0)
        }
    }

    func testSignedOutAndExpiredSessionsFailBeforeProfileStorageAccess() async throws {
        let local = ProfileMemoryStore()
        let cloud = ProfileCloudFake()
        let signedOut = ProfileSyncCoordinator(
            authentication: ProfileAuthenticationStub(session: nil),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        do {
            _ = try await signedOut.synchronize()
            XCTFail("Expected signed-out profile sync to fail")
        } catch let error as ProfileSyncCoordinatorError {
            XCTAssertEqual(error, .signedOut)
        }

        let expired = ProfileSyncCoordinator(
            authentication: ProfileAuthenticationStub(
                session: session(userID: "user-1", expiresAt: 400)
            ),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )

        do {
            _ = try await expired.synchronize()
            XCTFail("Expected expired profile sync to fail")
        } catch let error as ProfileSyncCoordinatorError {
            XCTAssertEqual(error, .expiredSession)
        }

        let loadCount = await local.loadCount()
        let fetchCount = await cloud.fetchCount()
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(fetchCount, 0)
    }

    private func makeCoordinator(
        userID: String,
        local: ProfileMemoryStore,
        cloud: ProfileCloudFake
    ) -> ProfileSyncCoordinator {
        ProfileSyncCoordinator(
            authentication: ProfileAuthenticationStub(session: session(userID: userID)),
            localRepository: local,
            cloudRepository: cloud,
            nowMilliseconds: { 500 }
        )
    }

    private func session(userID: String, expiresAt: TimeInterval = 1_000) -> AuthenticatedSession {
        AuthenticatedSession(
            userID: userID,
            email: nil,
            provider: .google,
            expiresAtMilliseconds: expiresAt
        )
    }

    private func profile(
        name: String,
        avatar: CatAvatar,
        updatedAt: TimeInterval
    ) -> LocalAccountProfile {
        LocalAccountProfile(
            displayName: name,
            avatar: avatar,
            updatedAtMilliseconds: updatedAt
        )
    }
}

private enum ProfileTestError: Error {
    case offline
    case missingSession
}

private actor ProfileAuthenticationStub: AuthenticationSessionServing {
    private let session: AuthenticatedSession?

    init(session: AuthenticatedSession?) {
        self.session = session
    }

    func currentSession() async throws -> AuthenticatedSession? {
        session
    }

    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession {
        guard let session else { throw ProfileTestError.missingSession }
        return session
    }

    func signOut() async throws {}
}

private actor ProfileMemoryStore: AccountProfileStoring {
    private var storage: [String: LocalAccountProfile]
    private var loads = 0
    private var saves = 0

    init(records: [String: LocalAccountProfile] = [:]) {
        storage = records
    }

    func profile(for userID: String) async throws -> LocalAccountProfile? {
        loads += 1
        return storage[userID]
    }

    func save(_ profile: LocalAccountProfile, for userID: String) async throws {
        saves += 1
        storage[userID] = profile
    }

    func loadCount() -> Int { loads }
    func saveCount() -> Int { saves }
}

private actor ProfileCloudFake: CloudProfileRepository {
    private var storage: [String: LocalAccountProfile]
    private var fetches = 0
    private var upserts = 0
    private var remainingUpsertFailures: Int
    private let shouldFailFetch: Bool

    init(
        records: [String: LocalAccountProfile] = [:],
        remainingUpsertFailures: Int = 0,
        shouldFailFetch: Bool = false
    ) {
        storage = records
        self.remainingUpsertFailures = remainingUpsertFailures
        self.shouldFailFetch = shouldFailFetch
    }

    func fetch(for userID: String) async throws -> LocalAccountProfile? {
        fetches += 1
        guard !shouldFailFetch else { throw ProfileTestError.offline }
        return storage[userID]
    }

    func upsert(_ profile: LocalAccountProfile, for userID: String) async throws {
        upserts += 1
        if remainingUpsertFailures > 0 {
            remainingUpsertFailures -= 1
            throw ProfileTestError.offline
        }
        storage[userID] = profile
    }

    func fetchCount() -> Int { fetches }
    func upsertCount() -> Int { upserts }
}
