import CryptoKit
import Foundation

struct SupabaseConfiguration: Equatable, Sendable {
    let baseURL: URL
    let publishableKey: String
    let callbackURL: URL

    static let production = Self(
        baseURL: URL(string: "https://iwtitkgzaxwvpzviypue.supabase.co")!,
        publishableKey: "sb_publishable_jZC7mTKs8dbX78jQwo-BEg_JeJ3pAYh",
        callbackURL: URL(string: "pawfolio://auth/callback")!
    )
}

struct SupabaseHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol SupabaseHTTPTransporting: Sendable {
    func response(for request: URLRequest) async throws -> SupabaseHTTPResponse
}

final class URLSessionSupabaseTransport: SupabaseHTTPTransporting, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func response(for request: URLRequest) async throws -> SupabaseHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        return SupabaseHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

protocol OAuthAuthorizationProviding: Sendable {
    @MainActor
    func authenticate(at authorizationURL: URL, callbackURLScheme: String) async throws -> URL
}

protocol SupabaseAccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

enum SupabaseServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case signedOut
    case sessionExpired
    case providerUnavailable(AuthenticationProvider)
    case oauthCancelled
    case oauthAlreadyInProgress
    case oauthCallbackInvalid
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Supabase 配置无效。"
        case .invalidResponse:
            "云端返回了无法识别的数据。"
        case .signedOut:
            "当前没有登录账号。"
        case .sessionExpired:
            "登录已过期，请重新登录。"
        case let .providerUnavailable(provider):
            provider == .apple
                ? "Sign in with Apple 将在配置 Apple Developer Team 后启用。"
                : "该登录方式暂不可用。"
        case .oauthCancelled:
            "登录已取消。"
        case .oauthAlreadyInProgress:
            "已有登录流程正在进行。"
        case .oauthCallbackInvalid:
            "登录回调无效，请检查 Supabase Redirect URL 配置。"
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "云端请求失败（\(statusCode)）：\(message)"
            } else {
                "云端请求失败（\(statusCode)）。"
            }
        }
    }
}

struct StoredSupabaseSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAtMilliseconds: TimeInterval
    let userID: String
    let email: String?
    let displayName: String?
    let provider: AuthenticationProvider

    init(
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        expiresAtMilliseconds: TimeInterval,
        userID: String,
        email: String?,
        displayName: String? = nil,
        provider: AuthenticationProvider
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAtMilliseconds = expiresAtMilliseconds
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.provider = provider
    }

    var publicSession: AuthenticatedSession {
        AuthenticatedSession(
            userID: userID,
            email: email,
            displayName: displayName,
            provider: provider,
            expiresAtMilliseconds: expiresAtMilliseconds
        )
    }
}

protocol SupabaseSessionStoring: Sendable {
    func load() async throws -> StoredSupabaseSession?
    func save(_ session: StoredSupabaseSession) async throws
    func delete() async throws
}

actor SupabaseAuthenticationService: AuthenticationSessionServing, SupabaseAccessTokenProviding {
    private struct TokenResponse: Decodable {
        struct User: Decodable {
            struct Metadata: Decodable {
                let fullName: String?
                let name: String?
                let preferredUsername: String?

                enum CodingKeys: String, CodingKey {
                    case fullName = "full_name"
                    case name
                    case preferredUsername = "preferred_username"
                }

                var preferredDisplayName: String? {
                    [fullName, name, preferredUsername]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty })
                }
            }

            let id: String
            let email: String?
            let metadata: Metadata?

            enum CodingKeys: String, CodingKey {
                case id
                case email
                case metadata = "user_metadata"
            }
        }

        let accessToken: String
        let refreshToken: String?
        let tokenType: String?
        let expiresIn: TimeInterval?
        let expiresAt: TimeInterval?
        let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }

    private struct PKCEExchangeBody: Encodable {
        let authCode: String
        let codeVerifier: String

        enum CodingKeys: String, CodingKey {
            case authCode = "auth_code"
            case codeVerifier = "code_verifier"
        }
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct ErrorPayload: Decodable {
        let message: String?
        let errorDescription: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case message
            case errorDescription = "error_description"
            case error
        }

        var bestMessage: String? {
            errorDescription ?? message ?? error
        }
    }

    private let configuration: SupabaseConfiguration
    private let sessionStore: any SupabaseSessionStoring
    private let transport: any SupabaseHTTPTransporting
    private let oauthAuthorizer: (any OAuthAuthorizationProviding)?
    private let nowMilliseconds: @Sendable () -> TimeInterval
    private let refreshLeewayMilliseconds: TimeInterval

    init(
        configuration: SupabaseConfiguration = .production,
        sessionStore: any SupabaseSessionStoring,
        transport: any SupabaseHTTPTransporting = URLSessionSupabaseTransport(),
        oauthAuthorizer: (any OAuthAuthorizationProviding)? = nil,
        nowMilliseconds: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970 * 1_000
        },
        refreshLeewayMilliseconds: TimeInterval = 60_000
    ) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.transport = transport
        self.oauthAuthorizer = oauthAuthorizer
        self.nowMilliseconds = nowMilliseconds
        self.refreshLeewayMilliseconds = refreshLeewayMilliseconds
    }

    func currentSession() async throws -> AuthenticatedSession? {
        guard let stored = try await sessionStore.load() else { return nil }
        do {
            return try await validSession(from: stored, forceRefresh: false).publicSession
        } catch SupabaseServiceError.sessionExpired {
            try? await sessionStore.delete()
            return nil
        }
    }

    func signIn(using provider: AuthenticationProvider) async throws -> AuthenticatedSession {
        guard provider == .google else {
            throw SupabaseServiceError.providerUnavailable(provider)
        }
        guard let oauthAuthorizer,
              let callbackScheme = configuration.callbackURL.scheme else {
            throw SupabaseServiceError.invalidConfiguration
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let authorizationURL = try makeAuthorizationURL(
            provider: provider,
            codeChallenge: challenge
        )
        let callbackURL: URL
        do {
            callbackURL = try await oauthAuthorizer.authenticate(
                at: authorizationURL,
                callbackURLScheme: callbackScheme
            )
        } catch is CancellationError {
            throw SupabaseServiceError.oauthCancelled
        }

        guard callbackURL.scheme?.caseInsensitiveCompare(callbackScheme) == .orderedSame,
              callbackURL.host?.caseInsensitiveCompare(configuration.callbackURL.host ?? "") == .orderedSame,
              callbackURL.path == configuration.callbackURL.path,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let authCode = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !authCode.isEmpty else {
            throw SupabaseServiceError.oauthCallbackInvalid
        }

        let tokenResponse: TokenResponse = try await post(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "pkce")],
            body: PKCEExchangeBody(authCode: authCode, codeVerifier: verifier)
        )
        let stored = try makeStoredSession(from: tokenResponse, provider: provider)
        try await sessionStore.save(stored)
        return stored.publicSession
    }

    func signOut() async throws {
        if let stored = try await sessionStore.load() {
            var request = URLRequest(url: endpoint(path: "auth/v1/logout"))
            request.httpMethod = "POST"
            applyHeaders(to: &request, accessToken: stored.accessToken)
            _ = try? await transport.response(for: request)
        }
        try await sessionStore.delete()
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        guard let stored = try await sessionStore.load() else {
            throw SupabaseServiceError.signedOut
        }
        return try await validSession(from: stored, forceRefresh: forceRefresh).accessToken
    }

    private func validSession(
        from stored: StoredSupabaseSession,
        forceRefresh: Bool
    ) async throws -> StoredSupabaseSession {
        let shouldRefresh = forceRefresh
            || stored.expiresAtMilliseconds <= nowMilliseconds() + refreshLeewayMilliseconds
        guard shouldRefresh else { return stored }
        guard !stored.refreshToken.isEmpty else {
            throw SupabaseServiceError.sessionExpired
        }

        let response: TokenResponse = try await post(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: RefreshBody(refreshToken: stored.refreshToken)
        )
        let refreshed = try makeStoredSession(
            from: response,
            provider: stored.provider,
            fallbackRefreshToken: stored.refreshToken,
            fallbackDisplayName: stored.displayName
        )
        try await sessionStore.save(refreshed)
        return refreshed
    }

    private func makeAuthorizationURL(
        provider: AuthenticationProvider,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(
            url: endpoint(path: "auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: configuration.callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let url = components?.url else {
            throw SupabaseServiceError.invalidConfiguration
        }
        return url
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        body: Body
    ) async throws -> Response {
        var components = URLComponents(url: endpoint(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SupabaseServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        applyHeaders(to: &request, accessToken: nil)
        request.httpBody = try JSONEncoder().encode(body)

        let response = try await transport.response(for: request)
        guard 200..<300 ~= response.statusCode else {
            if response.statusCode == 400 || response.statusCode == 401 {
                throw SupabaseServiceError.sessionExpired
            }
            throw responseError(from: response)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: response.data)
        } catch {
            throw SupabaseServiceError.invalidResponse
        }
    }

    private func makeStoredSession(
        from response: TokenResponse,
        provider: AuthenticationProvider,
        fallbackRefreshToken: String? = nil,
        fallbackDisplayName: String? = nil
    ) throws -> StoredSupabaseSession {
        let accessToken = response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = (response.refreshToken ?? fallbackRefreshToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = response.user.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty, !refreshToken.isEmpty, !userID.isEmpty else {
            throw SupabaseServiceError.invalidResponse
        }

        let expiresAtMilliseconds: TimeInterval
        if let expiresAt = response.expiresAt, expiresAt.isFinite, expiresAt > 0 {
            expiresAtMilliseconds = expiresAt * 1_000
        } else if let expiresIn = response.expiresIn, expiresIn.isFinite, expiresIn > 0 {
            expiresAtMilliseconds = nowMilliseconds() + expiresIn * 1_000
        } else {
            throw SupabaseServiceError.invalidResponse
        }

        return StoredSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: response.tokenType ?? "bearer",
            expiresAtMilliseconds: expiresAtMilliseconds,
            userID: userID,
            email: response.user.email,
            displayName: response.user.metadata?.preferredDisplayName ?? fallbackDisplayName,
            provider: provider
        )
    }

    private func endpoint(path: String) -> URL {
        configuration.baseURL.appendingPathComponent(path)
    }

    private func applyHeaders(to request: inout URLRequest, accessToken: String?) {
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken ?? configuration.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func responseError(from response: SupabaseHTTPResponse) -> SupabaseServiceError {
        let message = try? JSONDecoder().decode(ErrorPayload.self, from: response.data).bestMessage
        return .requestFailed(statusCode: response.statusCode, message: message)
    }

    private static func makeCodeVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement(using: &generator)! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

actor SupabaseCloudHoldingRepository: CloudHoldingRepository {
    private struct HoldingRow: Codable {
        let id: String
        let userID: String
        let payload: Holding
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case payload
            case updatedAt = "updated_at"
        }
    }

    private struct ReadRow: Decodable {
        let payload: Holding
    }

    private struct ErrorPayload: Decodable {
        let message: String?
        let details: String?

        var bestMessage: String? { message ?? details }
    }

    private let configuration: SupabaseConfiguration
    private let tokenProvider: any SupabaseAccessTokenProviding
    private let transport: any SupabaseHTTPTransporting

    init(
        configuration: SupabaseConfiguration = .production,
        tokenProvider: any SupabaseAccessTokenProviding,
        transport: any SupabaseHTTPTransporting = URLSessionSupabaseTransport()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    func fetchAll(for userID: String) async throws -> [Holding] {
        let normalizedUserID = try validatedUserID(userID)
        let url = try restURL(queryItems: [
            URLQueryItem(name: "select", value: "payload"),
            URLQueryItem(name: "user_id", value: "eq.\(normalizedUserID)"),
            URLQueryItem(name: "order", value: "updated_at.asc")
        ])
        let response = try await authorizedResponse(url: url, method: "GET")
        do {
            return try JSONDecoder().decode([ReadRow].self, from: response.data).map(\.payload)
        } catch {
            throw SupabaseServiceError.invalidResponse
        }
    }

    func upsert(_ holdings: [Holding], for userID: String) async throws {
        guard !holdings.isEmpty else { return }
        let normalizedUserID = try validatedUserID(userID)
        guard holdings.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw SupabaseServiceError.invalidResponse
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = holdings.map { holding in
            HoldingRow(
                id: holding.id,
                userID: normalizedUserID,
                payload: holding,
                updatedAt: formatter.string(
                    from: Date(timeIntervalSince1970: HoldingMerge.conflictTimestamp(for: holding) / 1_000)
                )
            )
        }
        let body = try JSONEncoder().encode(rows)
        let url = try restURL(queryItems: [
            URLQueryItem(name: "on_conflict", value: "user_id,id")
        ])
        _ = try await authorizedResponse(
            url: url,
            method: "POST",
            body: body,
            additionalHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    private func authorizedResponse(
        url: URL,
        method: String,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> SupabaseHTTPResponse {
        var token = try await tokenProvider.accessToken(forceRefresh: false)
        var response = try await send(
            url: url,
            method: method,
            body: body,
            token: token,
            additionalHeaders: additionalHeaders
        )
        if response.statusCode == 401 {
            token = try await tokenProvider.accessToken(forceRefresh: true)
            response = try await send(
                url: url,
                method: method,
                body: body,
                token: token,
                additionalHeaders: additionalHeaders
            )
        }
        guard 200..<300 ~= response.statusCode else {
            let error = try? JSONDecoder().decode(ErrorPayload.self, from: response.data)
            throw SupabaseServiceError.requestFailed(
                statusCode: response.statusCode,
                message: error?.bestMessage
            )
        }
        return response
    }

    private func send(
        url: URL,
        method: String,
        body: Data?,
        token: String,
        additionalHeaders: [String: String]
    ) async throws -> SupabaseHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await transport.response(for: request)
    }

    private func restURL(queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("rest/v1/holdings"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SupabaseServiceError.invalidConfiguration
        }
        return url
    }

    private func validatedUserID(_ userID: String) throws -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw HoldingSyncCoordinatorError.invalidUserIdentifier
        }
        return normalized
    }
}

actor SupabaseCloudProfileRepository: CloudProfileRepository {
    private struct ReadRow: Decodable {
        let displayName: String?
        let avatar: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatar
            case updatedAt = "updated_at"
        }
    }

    private struct WriteRow: Encodable {
        let userID: String
        let displayName: String?
        let avatar: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case displayName = "display_name"
            case avatar
            case updatedAt = "updated_at"
        }
    }

    private struct ErrorPayload: Decodable {
        let message: String?
        let details: String?

        var bestMessage: String? { message ?? details }
    }

    private let configuration: SupabaseConfiguration
    private let tokenProvider: any SupabaseAccessTokenProviding
    private let transport: any SupabaseHTTPTransporting

    init(
        configuration: SupabaseConfiguration = .production,
        tokenProvider: any SupabaseAccessTokenProviding,
        transport: any SupabaseHTTPTransporting = URLSessionSupabaseTransport()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    func fetch(for userID: String) async throws -> LocalAccountProfile? {
        let normalizedUserID = try validatedUserID(userID)
        let url = try restURL(queryItems: [
            URLQueryItem(name: "select", value: "display_name,avatar,updated_at"),
            URLQueryItem(name: "user_id", value: "eq.\(normalizedUserID)"),
            URLQueryItem(name: "limit", value: "1")
        ])
        let response = try await authorizedResponse(url: url, method: "GET")

        let rows: [ReadRow]
        do {
            rows = try JSONDecoder().decode([ReadRow].self, from: response.data)
        } catch {
            throw SupabaseServiceError.invalidResponse
        }
        guard let row = rows.first else { return nil }
        guard let avatarValue = row.avatar,
              let avatar = CatAvatar(rawValue: avatarValue),
              let updatedAtMilliseconds = Self.milliseconds(from: row.updatedAt) else {
            throw SupabaseServiceError.invalidResponse
        }

        return LocalAccountProfile(
            displayName: Self.normalizedDisplayName(row.displayName),
            avatar: avatar,
            updatedAtMilliseconds: updatedAtMilliseconds
        )
    }

    func upsert(_ profile: LocalAccountProfile, for userID: String) async throws {
        let normalizedUserID = try validatedUserID(userID)
        guard profile.updatedAtMilliseconds.isFinite,
              profile.updatedAtMilliseconds > 0 else {
            throw SupabaseServiceError.invalidResponse
        }

        let row = WriteRow(
            userID: normalizedUserID,
            displayName: Self.normalizedDisplayName(profile.displayName),
            avatar: profile.avatar.rawValue,
            updatedAt: Self.timestamp(from: profile.updatedAtMilliseconds)
        )
        let url = try restURL(queryItems: [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ])
        _ = try await authorizedResponse(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(row),
            additionalHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    private func authorizedResponse(
        url: URL,
        method: String,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> SupabaseHTTPResponse {
        var token = try await tokenProvider.accessToken(forceRefresh: false)
        var response = try await send(
            url: url,
            method: method,
            body: body,
            token: token,
            additionalHeaders: additionalHeaders
        )
        if response.statusCode == 401 {
            token = try await tokenProvider.accessToken(forceRefresh: true)
            response = try await send(
                url: url,
                method: method,
                body: body,
                token: token,
                additionalHeaders: additionalHeaders
            )
        }
        guard 200..<300 ~= response.statusCode else {
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: response.data)
            throw SupabaseServiceError.requestFailed(
                statusCode: response.statusCode,
                message: payload?.bestMessage
            )
        }
        return response
    }

    private func send(
        url: URL,
        method: String,
        body: Data?,
        token: String,
        additionalHeaders: [String: String]
    ) async throws -> SupabaseHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await transport.response(for: request)
    }

    private func restURL(queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("rest/v1/profiles"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SupabaseServiceError.invalidConfiguration
        }
        return url
    }

    private func validatedUserID(_ userID: String) throws -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 256 else {
            throw AccountProfileStoreError.invalidUserIdentifier
        }
        return normalized
    }

    private static func normalizedDisplayName(_ displayName: String?) -> String? {
        guard let normalized = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(20))
    }

    private static func timestamp(from milliseconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }

    private static func milliseconds(from timestamp: String) -> TimeInterval? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basicFormatter = ISO8601DateFormatter()
        basicFormatter.formatOptions = [.withInternetDateTime]
        guard let date = fractionalFormatter.date(from: timestamp)
            ?? basicFormatter.date(from: timestamp) else {
            return nil
        }
        return date.timeIntervalSince1970 * 1_000
    }
}
