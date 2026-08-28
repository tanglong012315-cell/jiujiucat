import Foundation

enum ProfileSyncState: Equatable, Sendable {
    case synchronized
    case pendingRemoteUpload
}

struct ProfileSyncOutcome: Equatable, Sendable {
    let userID: String
    let profile: LocalAccountProfile?
    let state: ProfileSyncState
}

enum ProfileSyncCoordinatorError: LocalizedError, Equatable {
    case signedOut
    case expiredSession
    case invalidUserIdentifier

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "登录状态已失效，请重新登录。"
        case .expiredSession:
            "登录已过期，请刷新会话后重试。"
        case .invalidUserIdentifier:
            "登录账号标识无效，无法同步个人资料。"
        }
    }
}

protocol ProfileSyncCoordinating: Sendable {
    func synchronize() async throws -> ProfileSyncOutcome
}

actor ProfileSyncCoordinator: ProfileSyncCoordinating {
    private let authentication: any AuthenticationSessionServing
    private let localRepository: any AccountProfileStoring
    private let cloudRepository: any CloudProfileRepository
    private let nowMilliseconds: @Sendable () -> TimeInterval

    init(
        authentication: any AuthenticationSessionServing,
        localRepository: any AccountProfileStoring,
        cloudRepository: any CloudProfileRepository,
        nowMilliseconds: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970 * 1_000
        }
    ) {
        self.authentication = authentication
        self.localRepository = localRepository
        self.cloudRepository = cloudRepository
        self.nowMilliseconds = nowMilliseconds
    }

    func synchronize() async throws -> ProfileSyncOutcome {
        guard let session = try await authentication.currentSession() else {
            throw ProfileSyncCoordinatorError.signedOut
        }
        guard !session.isExpired(at: nowMilliseconds()) else {
            throw ProfileSyncCoordinatorError.expiredSession
        }

        let userID = session.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw ProfileSyncCoordinatorError.invalidUserIdentifier
        }

        let local = try await localRepository.profile(for: userID)
        let remote = try await cloudRepository.fetch(for: userID)
        guard let merge = AccountProfileMerge.reconcile(local: local, remote: remote) else {
            return ProfileSyncOutcome(userID: userID, profile: nil, state: .synchronized)
        }

        if merge.shouldSaveLocally {
            try await localRepository.save(merge.profile, for: userID)
        }

        guard merge.shouldUploadRemotely else {
            return ProfileSyncOutcome(
                userID: userID,
                profile: merge.profile,
                state: .synchronized
            )
        }

        do {
            try await cloudRepository.upsert(merge.profile, for: userID)
            return ProfileSyncOutcome(
                userID: userID,
                profile: merge.profile,
                state: .synchronized
            )
        } catch {
            return ProfileSyncOutcome(
                userID: userID,
                profile: merge.profile,
                state: .pendingRemoteUpload
            )
        }
    }
}
