import XCTest
@testable import PawFolio

@MainActor
final class AccountViewModelTests: XCTestCase {
    func testLoginPresentationOnlyShowsWelcomeAfterIdentityExists() {
        XCTAssertEqual(
            LoginPresentationPhase(state: .signingIn(.google), isSignedIn: false),
            .authenticating
        )
        XCTAssertEqual(
            LoginPresentationPhase(state: .signingIn(.google), isSignedIn: true),
            .loadingAccount
        )
        XCTAssertEqual(
            LoginPresentationPhase(state: .syncing, isSignedIn: true),
            .loadingAccount
        )
    }

    func testLoginPresentationKeepsSessionRestoreTextFreeUntilIdentityExists() {
        XCTAssertEqual(
            LoginPresentationPhase(state: .restoringSession, isSignedIn: false),
            .authenticating
        )
        XCTAssertEqual(
            LoginPresentationPhase(state: .signedOut, isSignedIn: false),
            .idle
        )
        XCTAssertEqual(
            LoginPresentationPhase(
                state: .failed(message: "Login failed."),
                isSignedIn: false
            ),
            .idle
        )
    }

    func testSignInBuildsIdentityAndSwitchesToAccountScope() async throws {
        let userID = "account-1"
        let signedInSession = session(
            userID: userID,
            displayName: "Cloud Cat",
            provider: .google
        )
        let authentication = AccountAuthenticationFake(
            session: nil,
            signInBehavior: .succeed(signedInSession)
        )
        let model = makeModel(
            authentication: authentication,
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [
                outcome(userID: userID, holdings: [holding(id: "account-holding")])
            ]),
            decisions: AccountMemoryDecisionStore()
        )

        await model.loadIfNeeded()
        XCTAssertEqual(model.state, .signedOut)

        await model.signIn(using: .google)

        XCTAssertEqual(model.session, signedInSession)
        XCTAssertEqual(model.activeScope, .account(userID: userID))
        XCTAssertEqual(model.state, .synchronized(holdingCount: 1))
        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(
            model.identity,
            AccountIdentityPresentation(
                displayName: "Cloud Cat",
                maskedAccount: "ca••••@example.com",
                providerName: "Google",
                avatar: .faceHappy
            )
        )
    }

    func testSignInFailureKeepsSignedOutPresentationAndGuestScope() async throws {
        let authentication = AccountAuthenticationFake(
            session: nil,
            signInBehavior: .fail(.signInFailed)
        )
        let model = makeModel(
            authentication: authentication,
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: []),
            decisions: AccountMemoryDecisionStore()
        )

        await model.loadIfNeeded()
        await model.signIn(using: .google)

        XCTAssertEqual(model.state, .failed(message: "Login failed."))
        XCTAssertNil(model.session)
        XCTAssertNil(model.identity)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.activeScope, .guest)
    }

    func testCancelledOAuthUsesTheAccountCancellationMessage() async throws {
        let authentication = AccountAuthenticationFake(
            session: nil,
            signInBehavior: .oauthCancelled
        )
        let model = makeModel(
            authentication: authentication,
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: []),
            decisions: AccountMemoryDecisionStore()
        )

        await model.loadIfNeeded()
        await model.signIn(using: .google)

        XCTAssertEqual(model.state, .failed(message: "登录已取消。"))
        XCTAssertNil(model.identity)
        XCTAssertEqual(model.activeScope, .guest)
    }

    func testRestoredSessionWithGuestHoldingsRequiresExplicitChoiceBeforeSync() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository(records: [.guest: [holding(id: "guest")]])
        let sync = AccountSyncFake(outcomes: [outcome(userID: userID)])
        let decisions = AccountMemoryDecisionStore()
        let model = makeModel(
            authentication: authentication,
            local: local,
            sync: sync,
            decisions: decisions
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .guestImportRequired(count: 1))
        XCTAssertEqual(model.activeScope, .guest)
        let policies = await sync.receivedPolicies()
        XCTAssertTrue(policies.isEmpty)
    }

    func testLedgerOnlyGuestDataRequiresExplicitChoiceBeforeSync() async throws {
        let userID = "account-1"
        let sync = AccountSyncFake(outcomes: [outcome(userID: userID)])
        let ledgerImporter = AccountLedgerGuestImportFake(guestAssetCount: 2)
        let model = makeModel(
            authentication: AccountAuthenticationFake(session: session(userID: userID)),
            local: AccountMemoryHoldingRepository(),
            sync: sync,
            decisions: AccountMemoryDecisionStore(),
            ledgerImporter: ledgerImporter
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .guestImportRequired(count: 2))
        XCTAssertEqual(model.activeScope, .guest)
        let policies = await sync.receivedPolicies()
        XCTAssertTrue(policies.isEmpty)
    }

    func testCopyDecisionImportsLedgerBeforeSwitchingScope() async throws {
        let userID = "account-1"
        let guest = holding(id: "guest")
        let account = holding(id: "account")
        let ledgerImporter = AccountLedgerGuestImportFake(guestAssetCount: 1)
        let model = makeModel(
            authentication: AccountAuthenticationFake(session: session(userID: userID)),
            local: AccountMemoryHoldingRepository(records: [.guest: [guest]]),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID, holdings: [guest, account])]),
            decisions: AccountMemoryDecisionStore(),
            ledgerImporter: ledgerImporter
        )

        await model.loadIfNeeded()
        await model.chooseGuestImport(.copyIntoAccount)

        XCTAssertEqual(model.activeScope, .account(userID: userID))
        let calls = await ledgerImporter.copyCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].userID, userID)
        XCTAssertEqual(Set(calls[0].guestHoldings.map(\.id)), ["guest"])
        XCTAssertEqual(Set(calls[0].accountHoldings.map(\.id)), ["guest", "account"])
    }

    func testCopyDecisionRunsOnceAndRetryDoesNotRecopyGuestData() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository(records: [.guest: [holding(id: "guest")]])
        let sync = AccountSyncFake(outcomes: [
            outcome(userID: userID, holdings: [holding(id: "guest")]),
            outcome(userID: userID, holdings: [holding(id: "guest")])
        ])
        let decisions = AccountMemoryDecisionStore()
        let model = makeModel(
            authentication: authentication,
            local: local,
            sync: sync,
            decisions: decisions
        )

        await model.loadIfNeeded()
        await model.chooseGuestImport(.copyIntoAccount)

        let storedDecision = try await decisions.decision(for: userID)
        XCTAssertEqual(storedDecision, .copiedIntoAccount)
        XCTAssertEqual(model.state, .synchronized(holdingCount: 1))

        await model.retrySync()

        let policies = await sync.receivedPolicies()
        XCTAssertEqual(policies, [.copyIntoAccount, .keepSeparate])
    }

    func testPendingUploadCanBeRetriedManually() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository()
        let sync = AccountSyncFake(outcomes: [
            outcome(
                userID: userID,
                holdings: [holding(id: "local")],
                state: .pendingRemoteUpload(count: 1)
            ),
            outcome(userID: userID, holdings: [holding(id: "local")])
        ])
        let decisions = AccountMemoryDecisionStore(records: [userID: .keepSeparate])
        let model = makeModel(
            authentication: authentication,
            local: local,
            sync: sync,
            decisions: decisions
        )

        await model.loadIfNeeded()
        XCTAssertEqual(model.state, .pendingRemoteUpload(holdingCount: 1, pendingCount: 1))

        await model.retrySync()
        XCTAssertEqual(model.state, .synchronized(holdingCount: 1))
        let policies = await sync.receivedPolicies()
        XCTAssertEqual(policies, [.keepSeparate, .keepSeparate])
        let sessionReads = await authentication.currentSessionCallCount()
        XCTAssertEqual(sessionReads, 2)
    }

    func testSignOutSwitchesBackToGuestScope() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository()
        let sync = AccountSyncFake(outcomes: [outcome(userID: userID)])
        let decisions = AccountMemoryDecisionStore(records: [userID: .keepSeparate])
        let model = makeModel(
            authentication: authentication,
            local: local,
            sync: sync,
            decisions: decisions
        )

        await model.loadIfNeeded()
        XCTAssertEqual(model.activeScope, .account(userID: userID))

        await model.signOut()

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(model.session)
        XCTAssertEqual(model.activeScope, .guest)
    }

    func testStoredKeepSeparateDecisionSkipsImportPrompt() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository(records: [.guest: [holding(id: "guest")]])
        let sync = AccountSyncFake(outcomes: [outcome(userID: userID)])
        let decisions = AccountMemoryDecisionStore(records: [userID: .keepSeparate])
        let model = makeModel(
            authentication: authentication,
            local: local,
            sync: sync,
            decisions: decisions
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .synchronized(holdingCount: 0))
        let policies = await sync.receivedPolicies()
        XCTAssertEqual(policies, [.keepSeparate])
    }

    func testPausedCloudSyncRestoresAccountWithoutReadingGuestOrCallingCloud() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(session: session(userID: userID))
        let local = AccountMemoryHoldingRepository(records: [.guest: [holding(id: "guest")]])
        let sync = AccountSyncFake(outcomes: [])
        let decisions = AccountMemoryDecisionStore()
        let model = AccountViewModel(
            authentication: authentication,
            localRepository: local,
            syncCoordinator: sync,
            decisionStore: decisions,
            profileStore: AccountMemoryProfileStore(),
            cloudSyncAvailability: .paused(reason: "等待线上验证"),
            nowMilliseconds: { 500 }
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.session?.userID, userID)
        XCTAssertEqual(model.activeScope, .account(userID: userID))
        XCTAssertEqual(model.state, .syncPaused(message: "等待线上验证"))
        XCTAssertFalse(model.isCloudSyncEnabled)
        let policies = await sync.receivedPolicies()
        XCTAssertTrue(policies.isEmpty)
    }

    func testIdentityUsesProviderNameAndNeverExposesFullEmail() async throws {
        let userID = "account-1"
        let authentication = AccountAuthenticationFake(
            session: session(userID: userID, displayName: "Cloud Cat")
        )
        let model = makeModel(
            authentication: authentication,
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID)]),
            decisions: AccountMemoryDecisionStore(records: [userID: .keepSeparate])
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.identity?.displayName, "Cloud Cat")
        XCTAssertEqual(model.identity?.providerName, "Apple")
        XCTAssertEqual(model.identity?.maskedAccount, "ca••••@example.com")
        XCTAssertFalse(model.identity?.maskedAccount.contains("cat@example.com") == true)
    }

    func testStoredLocalProfileOverridesProviderPresentation() async throws {
        let userID = "account-1"
        let profiles = AccountMemoryProfileStore(records: [
            userID: LocalAccountProfile(displayName: "雪球", avatar: .faceCute)
        ])
        let model = makeModel(
            authentication: AccountAuthenticationFake(
                session: session(userID: userID, displayName: "Cloud Cat")
            ),
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID)]),
            decisions: AccountMemoryDecisionStore(records: [userID: .keepSeparate]),
            profiles: profiles
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.identity?.displayName, "雪球")
        XCTAssertEqual(model.identity?.avatar, .faceCute)
    }

    func testSavingProfileUpdatesPresentationAndPersistsPerAccount() async throws {
        let userID = "account-1"
        let profiles = AccountMemoryProfileStore()
        let model = makeModel(
            authentication: AccountAuthenticationFake(session: session(userID: userID)),
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID)]),
            decisions: AccountMemoryDecisionStore(records: [userID: .keepSeparate]),
            profiles: profiles
        )
        await model.loadIfNeeded()

        let saved = await model.saveProfile(displayName: "  橘猫  ", avatar: .catJiujiu)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.identity?.displayName, "橘猫")
        XCTAssertEqual(model.identity?.avatar, .catJiujiu)
        let stored = try await profiles.profile(for: userID)
        XCTAssertEqual(stored?.displayName, "橘猫")
        XCTAssertEqual(stored?.avatar, .catJiujiu)
        XCTAssertEqual(stored?.updatedAtMilliseconds, 500)
    }

    func testProfileSyncOutcomeUpdatesIdentityWithoutChangingHoldingState() async throws {
        let userID = "account-1"
        let remoteProfile = LocalAccountProfile(
            displayName: "Cloud Cat",
            avatar: .catPuffy,
            updatedAtMilliseconds: 400
        )
        let profileSync = AccountProfileSyncFake(results: [
            .success(ProfileSyncOutcome(
                userID: userID,
                profile: remoteProfile,
                state: .synchronized
            ))
        ])
        let model = makeModel(
            authentication: AccountAuthenticationFake(session: session(userID: userID)),
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID)]),
            decisions: AccountMemoryDecisionStore(records: [userID: .keepSeparate]),
            profileSync: profileSync
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .synchronized(holdingCount: 0))
        XCTAssertEqual(model.profileSyncState, .synchronized)
        XCTAssertEqual(model.identity?.displayName, "Cloud Cat")
        XCTAssertEqual(model.identity?.avatar, .catPuffy)
    }

    func testProfileSyncFailureDoesNotTurnSuccessfulHoldingSyncIntoFailure() async throws {
        let userID = "account-1"
        let model = makeModel(
            authentication: AccountAuthenticationFake(session: session(userID: userID)),
            local: AccountMemoryHoldingRepository(),
            sync: AccountSyncFake(outcomes: [outcome(userID: userID)]),
            decisions: AccountMemoryDecisionStore(records: [userID: .keepSeparate]),
            profileSync: AccountProfileSyncFake(results: [.failure])
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .synchronized(holdingCount: 0))
        XCTAssertEqual(
            model.profileSyncState,
            .failed(message: "个人资料网络暂不可用。")
        )
    }

    private func makeModel(
        authentication: AccountAuthenticationFake,
        local: AccountMemoryHoldingRepository,
        sync: AccountSyncFake,
        decisions: AccountMemoryDecisionStore,
        profiles: AccountMemoryProfileStore = AccountMemoryProfileStore(),
        profileSync: AccountProfileSyncFake? = nil,
        ledgerImporter: AccountLedgerGuestImportFake? = nil
    ) -> AccountViewModel {
        AccountViewModel(
            authentication: authentication,
            localRepository: local,
            syncCoordinator: sync,
            decisionStore: decisions,
            profileStore: profiles,
            profileSyncCoordinator: profileSync,
            ledgerGuestImporter: ledgerImporter,
            nowMilliseconds: { 500 }
        )
    }

    private func session(
        userID: String,
        displayName: String? = nil,
        provider: AuthenticationProvider = .apple
    ) -> AuthenticatedSession {
        AuthenticatedSession(
            userID: userID,
            email: "cat@example.com",
            displayName: displayName,
            provider: provider,
            expiresAtMilliseconds: 1_000
        )
    }

    private func holding(id: String) -> Holding {
        Holding(
            id: id,
            symbol: "AAPL",
            holdingKind: .market,
            quantity: 1,
            costPerShare: 100,
            createdAt: 100,
            updatedAt: 200
        )
    }

    private func outcome(
        userID: String,
        holdings: [Holding] = [],
        state: HoldingSyncState = .synchronized
    ) -> HoldingSyncOutcome {
        HoldingSyncOutcome(
            userID: userID,
            holdings: holdings,
            state: state,
            copiedGuestHoldingCount: 0
        )
    }
}

@MainActor
final class LanguagePreferenceStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "pawfolio.tests.language.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToEnglish() {
        let store = LanguagePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.selected, .english)
        XCTAssertEqual(store.selected.localeIdentifier, "en")
    }

    func testRestoresLegacyChinesePreference() {
        defaults.set("zh", forKey: "pawfolio.language")

        let store = LanguagePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.selected, .chinese)
        XCTAssertEqual(store.selected.localeIdentifier, "zh-Hans")
    }

    func testSelectionPersistsImmediately() {
        let store = LanguagePreferenceStore(defaults: defaults)

        store.selected = .chinese

        XCTAssertEqual(defaults.string(forKey: "pawfolio.language"), "zh")
        XCTAssertEqual(LanguagePreferenceStore(defaults: defaults).selected, .chinese)
    }
}

final class LocalizationResourceTests: XCTestCase {
    func testProfessionalSimplifiedChineseStringsAreBundled() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))

        XCTAssertEqual(bundle.localizedString(forKey: "tab.currency", value: nil, table: nil), "汇率")
        XCTAssertEqual(bundle.localizedString(forKey: "Subscribe", value: nil, table: nil), "申购")
        XCTAssertEqual(bundle.localizedString(forKey: "Reverse transaction", value: nil, table: nil), "冲正交易")
        XCTAssertEqual(bundle.localizedString(forKey: "Total PNL", value: nil, table: nil), "总盈亏")
        XCTAssertEqual(bundle.localizedString(forKey: "Daily (USD)", value: nil, table: nil), "每日（USD）")
        XCTAssertEqual(bundle.localizedString(forKey: "Received (USD)", value: nil, table: nil), "已发放（USD）")
        XCTAssertEqual(bundle.localizedString(forKey: "Next Payout", value: nil, table: nil), "下次派息")

        let buyFormat = bundle.localizedString(forKey: "Buy %@", value: nil, table: nil)
        XCTAssertEqual(String(format: buyFormat, locale: Locale(identifier: "zh-Hans"), "BTC"), "买入 BTC")
    }
}

private actor AccountLedgerGuestImportFake: LedgerGuestImporting {
    struct CopyCall: Sendable {
        let userID: String
        let guestHoldings: [Holding]
        let accountHoldings: [Holding]
    }

    private let count: Int
    private var calls: [CopyCall] = []

    init(guestAssetCount: Int) {
        count = guestAssetCount
    }

    func guestAssetCount(guestHoldings: [Holding], openingAt: Date) async throws -> Int {
        count
    }

    func copyGuestLedgerIntoAccount(
        userID: String,
        guestHoldings: [Holding],
        accountHoldings: [Holding],
        openingAt: Date
    ) async throws {
        calls.append(CopyCall(
            userID: userID,
            guestHoldings: guestHoldings,
            accountHoldings: accountHoldings
        ))
    }

    func copyCalls() -> [CopyCall] { calls }
}

private enum AccountAuthenticationSignInBehavior: Sendable {
    case currentSession
    case succeed(AuthenticatedSession)
    case fail(AccountTestError)
    case oauthCancelled
}

private actor AccountAuthenticationFake: AuthenticationSessionServing {
    private var session: AuthenticatedSession?
    private var currentSessionCalls = 0
    private let signInBehavior: AccountAuthenticationSignInBehavior

    init(
        session: AuthenticatedSession?,
        signInBehavior: AccountAuthenticationSignInBehavior = .currentSession
    ) {
        self.session = session
        self.signInBehavior = signInBehavior
    }

    func currentSession() async throws -> AuthenticatedSession? {
        currentSessionCalls += 1
        return session
    }

    func currentSessionCallCount() -> Int {
        currentSessionCalls
    }

    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession {
        switch signInBehavior {
        case .currentSession:
            guard let session else { throw AccountTestError.missingSession }
            return session
        case .succeed(let signedInSession):
            session = signedInSession
            return signedInSession
        case .fail(let error):
            throw error
        case .oauthCancelled:
            throw SupabaseServiceError.oauthCancelled
        }
    }

    func signOut() async throws {
        session = nil
    }
}

private actor AccountMemoryHoldingRepository: ScopedHoldingRepository {
    private var storage: [HoldingStorageScope: [Holding]]

    init(records: [HoldingStorageScope: [Holding]] = [:]) {
        storage = records
    }

    func load(for scope: HoldingStorageScope) async throws -> [Holding] {
        storage[scope] ?? []
    }

    func save(_ holdings: [Holding], for scope: HoldingStorageScope) async throws {
        storage[scope] = holdings
    }
}

private actor AccountMemoryDecisionStore: GuestImportDecisionStoring {
    private var records: [String: GuestImportDecision]

    init(records: [String: GuestImportDecision] = [:]) {
        self.records = records
    }

    func decision(for userID: String) async throws -> GuestImportDecision? {
        records[userID]
    }

    func save(_ decision: GuestImportDecision, for userID: String) async throws {
        records[userID] = decision
    }
}

private actor AccountSyncFake: HoldingSyncCoordinating {
    private var outcomes: [HoldingSyncOutcome]
    private var policies: [GuestHoldingImportPolicy] = []

    init(outcomes: [HoldingSyncOutcome]) {
        self.outcomes = outcomes
    }

    func synchronize(
        guestImportPolicy: GuestHoldingImportPolicy
    ) async throws -> HoldingSyncOutcome {
        policies.append(guestImportPolicy)
        guard !outcomes.isEmpty else { throw AccountTestError.missingOutcome }
        return outcomes.removeFirst()
    }

    func receivedPolicies() -> [GuestHoldingImportPolicy] {
        policies
    }
}

private actor AccountMemoryProfileStore: AccountProfileStoring {
    private var records: [String: LocalAccountProfile]

    init(records: [String: LocalAccountProfile] = [:]) {
        self.records = records
    }

    func profile(for userID: String) async throws -> LocalAccountProfile? {
        records[userID]
    }

    func save(_ profile: LocalAccountProfile, for userID: String) async throws {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[userID] = LocalAccountProfile(
            displayName: name?.isEmpty == false ? name : nil,
            avatar: profile.avatar,
            updatedAtMilliseconds: profile.updatedAtMilliseconds
        )
    }
}

private enum AccountProfileSyncFakeResult: Sendable {
    case success(ProfileSyncOutcome)
    case failure
}

private actor AccountProfileSyncFake: ProfileSyncCoordinating {
    private var results: [AccountProfileSyncFakeResult]

    init(results: [AccountProfileSyncFakeResult]) {
        self.results = results
    }

    func synchronize() async throws -> ProfileSyncOutcome {
        guard !results.isEmpty else { throw AccountTestError.missingOutcome }
        switch results.removeFirst() {
        case let .success(outcome):
            return outcome
        case .failure:
            throw AccountTestError.profileOffline
        }
    }
}

private enum AccountTestError: LocalizedError, Sendable {
    case missingSession
    case missingOutcome
    case profileOffline
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .profileOffline:
            "个人资料网络暂不可用。"
        case .signInFailed:
            "Login failed."
        case .missingSession, .missingOutcome:
            nil
        }
    }
}
