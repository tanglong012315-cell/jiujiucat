import Foundation

enum AuthenticationProvider: String, Codable, CaseIterable, Sendable {
    case apple
    case google
}

struct AuthenticatedSession: Equatable, Sendable {
    let userID: String
    let email: String?
    let displayName: String?
    let provider: AuthenticationProvider
    let expiresAtMilliseconds: TimeInterval?

    init(
        userID: String,
        email: String?,
        displayName: String? = nil,
        provider: AuthenticationProvider,
        expiresAtMilliseconds: TimeInterval?
    ) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.expiresAtMilliseconds = expiresAtMilliseconds
    }

    func isExpired(at timestampMilliseconds: TimeInterval) -> Bool {
        guard let expiresAtMilliseconds else { return false }
        return timestampMilliseconds >= expiresAtMilliseconds
    }
}

protocol AuthenticationSessionServing: Sendable {
    func currentSession() async throws -> AuthenticatedSession?
    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession
    func signOut() async throws
}

protocol CloudHoldingRepository: Sendable {
    func fetchAll(for userID: String) async throws -> [Holding]

    // Implementations upsert every supplied payload, including tombstones.
    // Absence from this array must never be interpreted as permission to delete a row.
    func upsert(_ holdings: [Holding], for userID: String) async throws
}

enum AccountConfigurationError: LocalizedError {
    case authenticationNotConfigured
    case cloudSyncNotConfigured

    var errorDescription: String? {
        switch self {
        case .authenticationNotConfigured:
            "登录服务尚未配置。请先添加 Supabase 与 OAuth 配置。"
        case .cloudSyncNotConfigured:
            "云同步服务尚未配置。"
        }
    }
}

actor UnavailableAuthenticationSessionService: AuthenticationSessionServing {
    func currentSession() async throws -> AuthenticatedSession? {
        nil
    }

    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession {
        throw AccountConfigurationError.authenticationNotConfigured
    }

    func signOut() async throws {}
}

actor UnavailableCloudHoldingRepository: CloudHoldingRepository {
    func fetchAll(for userID: String) async throws -> [Holding] {
        throw AccountConfigurationError.cloudSyncNotConfigured
    }

    func upsert(_ holdings: [Holding], for userID: String) async throws {
        throw AccountConfigurationError.cloudSyncNotConfigured
    }
}
