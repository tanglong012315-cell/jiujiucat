import Combine
import Foundation

enum AccountSyncPresentationState: Equatable {
    case restoringSession
    case signedOut
    case signingIn(AuthenticationProvider)
    case guestImportRequired(count: Int)
    case syncing
    case synchronized(holdingCount: Int)
    case pendingRemoteUpload(holdingCount: Int, pendingCount: Int)
    case syncPaused(message: String)
    case failed(message: String)
}

enum AccountCloudSyncAvailability: Equatable, Sendable {
    case enabled
    case paused(reason: String)
}

enum AccountProfileSyncPresentationState: Equatable, Sendable {
    case localOnly
    case syncing
    case synchronized
    case pendingRemoteUpload
    case failed(message: String)
}

struct AccountIdentityPresentation: Equatable, Sendable {
    let displayName: String
    let maskedAccount: String
    let providerName: String
    let avatar: CatAvatar
}

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var state: AccountSyncPresentationState = .restoringSession
    @Published private(set) var session: AuthenticatedSession?
    @Published private(set) var activeScope: HoldingStorageScope = .guest
    @Published private(set) var identity: AccountIdentityPresentation?
    @Published private(set) var isSavingProfile = false
    @Published private(set) var profileErrorMessage: String?
    @Published private(set) var profileSyncState: AccountProfileSyncPresentationState = .localOnly

    private let authentication: any AuthenticationSessionServing
    private let localRepository: any ScopedHoldingRepository
    private let syncCoordinator: any HoldingSyncCoordinating
    private let decisionStore: any GuestImportDecisionStoring
    private let profileStore: any AccountProfileStoring
    private let profileSyncCoordinator: (any ProfileSyncCoordinating)?
    private let cloudSyncAvailability: AccountCloudSyncAvailability
    private let nowMilliseconds: @Sendable () -> TimeInterval
    private var localProfile = LocalAccountProfile()
    private var hasLoaded = false
    private var isPerformingAction = false

    init(
        authentication: any AuthenticationSessionServing,
        localRepository: any ScopedHoldingRepository,
        syncCoordinator: any HoldingSyncCoordinating,
        decisionStore: any GuestImportDecisionStoring,
        profileStore: any AccountProfileStoring,
        profileSyncCoordinator: (any ProfileSyncCoordinating)? = nil,
        cloudSyncAvailability: AccountCloudSyncAvailability = .enabled,
        nowMilliseconds: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970 * 1_000
        }
    ) {
        self.authentication = authentication
        self.localRepository = localRepository
        self.syncCoordinator = syncCoordinator
        self.decisionStore = decisionStore
        self.profileStore = profileStore
        self.profileSyncCoordinator = profileSyncCoordinator
        self.cloudSyncAvailability = cloudSyncAvailability
        self.nowMilliseconds = nowMilliseconds
    }

    var isBusy: Bool {
        switch state {
        case .restoringSession, .signingIn, .syncing:
            true
        default:
            false
        }
    }

    var isCloudSyncEnabled: Bool {
        cloudSyncAvailability == .enabled
    }

    var isSignedIn: Bool {
        identity != nil
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await restoreSession()
    }

    func signIn(using provider: AuthenticationProvider) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        state = .signingIn(provider)
        defer { isPerformingAction = false }

        do {
            let signedInSession = try await authentication.signIn(using: provider)
            try await prepareAuthenticatedSession(signedInSession)
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    func chooseGuestImport(_ policy: GuestHoldingImportPolicy) async {
        guard !isPerformingAction, let session else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            switch policy {
            case .keepSeparate:
                try await decisionStore.save(.keepSeparate, for: session.userID)
                try await synchronize(using: .keepSeparate, session: session)
            case .copyIntoAccount:
                try await synchronize(using: .copyIntoAccount, session: session)
                // Mark the copy only after the coordinator has persisted the merged
                // account state. Future syncs must not act like a continuing link.
                try await decisionStore.save(.copiedIntoAccount, for: session.userID)
            }
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    func retrySync() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            guard let refreshedSession = try await authentication.currentSession() else {
                session = nil
                identity = nil
                localProfile = LocalAccountProfile()
                profileErrorMessage = nil
                profileSyncState = .localOnly
                switchScope(to: .guest)
                state = .signedOut
                return
            }
            try await prepareAuthenticatedSession(refreshedSession)
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    func saveProfile(displayName: String, avatar: CatAvatar) async -> Bool {
        guard !isSavingProfile, let session else { return false }
        isSavingProfile = true
        profileErrorMessage = nil
        defer { isSavingProfile = false }

        do {
            let profile = LocalAccountProfile(
                displayName: displayName,
                avatar: avatar,
                updatedAtMilliseconds: nowMilliseconds()
            )
            try await profileStore.save(profile, for: session.userID)
            localProfile = try await profileStore.profile(for: session.userID) ?? profile
            identity = Self.makeIdentity(session: session, profile: localProfile)
            await synchronizeProfileIfEnabled(session: session)
            return true
        } catch {
            profileErrorMessage = Self.message(for: error)
            return false
        }
    }

    func clearProfileError() {
        profileErrorMessage = nil
    }

    func signOut() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await authentication.signOut()
            session = nil
            identity = nil
            localProfile = LocalAccountProfile()
            profileErrorMessage = nil
            profileSyncState = .localOnly
            switchScope(to: .guest)
            state = .signedOut
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    private func restoreSession() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        state = .restoringSession
        defer { isPerformingAction = false }

        do {
            guard let restoredSession = try await authentication.currentSession() else {
                session = nil
                identity = nil
                switchScope(to: .guest)
                state = .signedOut
                return
            }
            try await prepareAuthenticatedSession(restoredSession)
        } catch {
            session = nil
            identity = nil
            switchScope(to: .guest)
            state = .failed(message: Self.message(for: error))
        }
    }

    private func prepareAuthenticatedSession(_ candidate: AuthenticatedSession) async throws {
        let userID = candidate.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw HoldingSyncCoordinatorError.invalidUserIdentifier
        }
        guard !candidate.isExpired(at: nowMilliseconds()) else {
            throw HoldingSyncCoordinatorError.expiredSession
        }

        session = candidate
        do {
            localProfile = try await profileStore.profile(for: userID) ?? LocalAccountProfile()
            profileErrorMessage = nil
        } catch {
            localProfile = LocalAccountProfile()
            profileErrorMessage = Self.message(for: error)
        }
        identity = Self.makeIdentity(session: candidate, profile: localProfile)
        await synchronizeProfileIfEnabled(session: candidate)
        switchScope(to: .account(userID: userID))

        if case let .paused(reason) = cloudSyncAvailability {
            state = .syncPaused(message: reason)
            return
        }

        let decision = try await decisionStore.decision(for: userID)
        if decision == nil {
            let guestHoldings = try await localRepository.load(for: .guest)
            let guestCount = guestHoldings.filter { !$0.isDeleted }.count
            if guestCount > 0 {
                state = .guestImportRequired(count: guestCount)
                return
            }
        }

        try await synchronize(using: .keepSeparate, session: candidate)
    }

    private func synchronize(
        using policy: GuestHoldingImportPolicy,
        session: AuthenticatedSession
    ) async throws {
        state = .syncing
        let outcome = try await syncCoordinator.synchronize(guestImportPolicy: policy)
        guard outcome.userID == session.userID.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw HoldingSyncCoordinatorError.invalidUserIdentifier
        }

        switch outcome.state {
        case .synchronized:
            state = .synchronized(holdingCount: outcome.holdings.filter { !$0.isDeleted }.count)
        case let .pendingRemoteUpload(count):
            state = .pendingRemoteUpload(
                holdingCount: outcome.holdings.filter { !$0.isDeleted }.count,
                pendingCount: count
            )
        }
    }

    private func switchScope(to scope: HoldingStorageScope) {
        activeScope = scope
    }

    private func synchronizeProfileIfEnabled(session: AuthenticatedSession) async {
        guard let profileSyncCoordinator else {
            profileSyncState = .localOnly
            return
        }

        profileSyncState = .syncing
        do {
            let outcome = try await profileSyncCoordinator.synchronize()
            let expectedUserID = session.userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard outcome.userID == expectedUserID else {
                throw ProfileSyncCoordinatorError.invalidUserIdentifier
            }

            if let profile = outcome.profile {
                localProfile = profile
                identity = Self.makeIdentity(session: session, profile: profile)
            }
            switch outcome.state {
            case .synchronized:
                profileSyncState = .synchronized
            case .pendingRemoteUpload:
                profileSyncState = .pendingRemoteUpload
            }
        } catch {
            profileSyncState = .failed(message: Self.message(for: error))
        }
    }

    private static func makeIdentity(
        session: AuthenticatedSession,
        profile: LocalAccountProfile
    ) -> AccountIdentityPresentation {
        let localName = normalizedDisplayName(profile.displayName)
        let providerName = normalizedDisplayName(session.displayName)
        return AccountIdentityPresentation(
            displayName: localName ?? providerName ?? "PawFolio 账户",
            maskedAccount: maskedAccount(email: session.email, userID: session.userID),
            providerName: session.provider == .apple ? "Apple" : "Google",
            avatar: profile.avatar
        )
    }

    static func maskedAccount(email: String?, userID: String) -> String {
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
           let separator = email.lastIndex(of: "@"),
           separator != email.startIndex {
            let localPart = String(email[..<separator])
            let domain = String(email[email.index(after: separator)...])
            if !domain.isEmpty {
                let visiblePrefix = String(localPart.prefix(min(2, localPart.count)))
                return "\(visiblePrefix)••••@\(domain)"
            }
        }

        let normalizedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedID.count > 8 else { return normalizedID }
        return "\(normalizedID.prefix(4))••••\(normalizedID.suffix(4))"
    }

    private static func normalizedDisplayName(_ name: String?) -> String? {
        guard let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
