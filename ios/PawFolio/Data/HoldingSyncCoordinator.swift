import Foundation

enum GuestHoldingImportPolicy: String, Codable, CaseIterable, Sendable {
    case keepSeparate
    case copyIntoAccount
}

enum HoldingSyncState: Equatable, Sendable {
    case synchronized
    case pendingRemoteUpload(count: Int)
}

struct HoldingSyncOutcome: Equatable, Sendable {
    let userID: String
    let holdings: [Holding]
    let state: HoldingSyncState
    let copiedGuestHoldingCount: Int
}

enum HoldingSyncCoordinatorError: LocalizedError {
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
            "登录账号标识无效，无法同步持仓。"
        }
    }
}

actor HoldingSyncCoordinator {
    private let authentication: any AuthenticationSessionServing
    private let localRepository: any ScopedHoldingRepository
    private let cloudRepository: any CloudHoldingRepository
    private let nowMilliseconds: @Sendable () -> TimeInterval

    init(
        authentication: any AuthenticationSessionServing,
        localRepository: any ScopedHoldingRepository,
        cloudRepository: any CloudHoldingRepository,
        nowMilliseconds: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970 * 1_000
        }
    ) {
        self.authentication = authentication
        self.localRepository = localRepository
        self.cloudRepository = cloudRepository
        self.nowMilliseconds = nowMilliseconds
    }

    func synchronize(
        guestImportPolicy: GuestHoldingImportPolicy
    ) async throws -> HoldingSyncOutcome {
        guard let session = try await authentication.currentSession() else {
            throw HoldingSyncCoordinatorError.signedOut
        }
        guard !session.isExpired(at: nowMilliseconds()) else {
            throw HoldingSyncCoordinatorError.expiredSession
        }

        let userID = session.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw HoldingSyncCoordinatorError.invalidUserIdentifier
        }

        let accountScope = HoldingStorageScope.account(userID: userID)
        let accountHoldings = try await localRepository.load(for: accountScope)
        let guestHoldings: [Holding]
        switch guestImportPolicy {
        case .keepSeparate:
            guestHoldings = []
        case .copyIntoAccount:
            guestHoldings = try await localRepository.load(for: .guest)
        }

        let localCandidate: [Holding]
        if guestHoldings.isEmpty {
            localCandidate = accountHoldings
        } else {
            localCandidate = HoldingMerge.reconcile(
                local: accountHoldings + guestHoldings,
                remote: []
            ).holdings
        }

        let remoteHoldings = try await cloudRepository.fetchAll(for: userID)
        let merge = HoldingMerge.reconcile(local: localCandidate, remote: remoteHoldings)

        // Local persistence happens first. If the network write fails, the next
        // run compares this saved winner set with the cloud and recreates the delta.
        try await localRepository.save(merge.holdings, for: accountScope)

        guard !merge.remoteUpserts.isEmpty else {
            return HoldingSyncOutcome(
                userID: userID,
                holdings: merge.holdings,
                state: .synchronized,
                copiedGuestHoldingCount: guestHoldings.count
            )
        }

        do {
            try await cloudRepository.upsert(merge.remoteUpserts, for: userID)
            return HoldingSyncOutcome(
                userID: userID,
                holdings: merge.holdings,
                state: .synchronized,
                copiedGuestHoldingCount: guestHoldings.count
            )
        } catch {
            return HoldingSyncOutcome(
                userID: userID,
                holdings: merge.holdings,
                state: .pendingRemoteUpload(count: merge.remoteUpserts.count),
                copiedGuestHoldingCount: guestHoldings.count
            )
        }
    }
}

protocol HoldingSyncCoordinating: Sendable {
    func synchronize(
        guestImportPolicy: GuestHoldingImportPolicy
    ) async throws -> HoldingSyncOutcome
}

extension HoldingSyncCoordinator: HoldingSyncCoordinating {}
