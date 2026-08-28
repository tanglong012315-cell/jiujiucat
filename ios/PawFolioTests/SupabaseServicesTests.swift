import CryptoKit
import Foundation
import XCTest
@testable import PawFolio

@MainActor
final class SupabaseServicesTests: XCTestCase {
    private let configuration = SupabaseConfiguration(
        baseURL: URL(string: "https://example.supabase.co")!,
        publishableKey: "publishable-test-key",
        callbackURL: URL(string: "pawfolio://auth/callback")!
    )

    func testGoogleSignInUsesPKCEAndStoresReturnedSession() async throws {
        let store = MemorySupabaseSessionStore()
        let authorizer = OAuthAuthorizerSpy(
            callbackURL: URL(string: "pawfolio://auth/callback?code=authorization-code")!
        )
        let transport = SupabaseTransportSpy(responses: [
            response(
                statusCode: 200,
                json: """
                {
                  "access_token": "access-1",
                  "refresh_token": "refresh-1",
                  "token_type": "bearer",
                  "expires_in": 3600,
                  "user": {
                    "id": "user-1",
                    "email": "cat@example.com",
                    "user_metadata": { "full_name": "Snow Cat" }
                  }
                }
                """
            )
        ])
        let service = SupabaseAuthenticationService(
            configuration: configuration,
            sessionStore: store,
            transport: transport,
            oauthAuthorizer: authorizer,
            nowMilliseconds: { 1_000 }
        )

        let session = try await service.signIn(using: .google)

        XCTAssertEqual(session.userID, "user-1")
        XCTAssertEqual(session.email, "cat@example.com")
        XCTAssertEqual(session.displayName, "Snow Cat")
        XCTAssertEqual(session.provider, .google)
        XCTAssertEqual(session.expiresAtMilliseconds, 3_601_000)

        let authorizationURL = try XCTUnwrap(authorizer.authorizationURL)
        let authorizationItems = try XCTUnwrap(
            URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(value(named: "provider", in: authorizationItems), "google")
        XCTAssertEqual(
            value(named: "redirect_to", in: authorizationItems),
            "pawfolio://auth/callback"
        )
        XCTAssertEqual(value(named: "code_challenge_method", in: authorizationItems), "s256")

        let requests = await transport.recordedRequests()
        let tokenRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.url?.path, "/auth/v1/token")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(tokenRequest.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "grant_type" })?.value,
            "pkce"
        )
        let body = try jsonObject(from: try XCTUnwrap(tokenRequest.httpBody))
        XCTAssertEqual(body["auth_code"] as? String, "authorization-code")
        let verifier = try XCTUnwrap(body["code_verifier"] as? String)
        XCTAssertEqual(value(named: "code_challenge", in: authorizationItems), challenge(for: verifier))

        let stored = try await store.load()
        XCTAssertEqual(stored?.accessToken, "access-1")
        XCTAssertEqual(stored?.refreshToken, "refresh-1")
    }

    func testAppleSignInStaysUnavailableWithoutDeveloperTeam() async throws {
        let transport = SupabaseTransportSpy()
        let service = SupabaseAuthenticationService(
            configuration: configuration,
            sessionStore: MemorySupabaseSessionStore(),
            transport: transport,
            oauthAuthorizer: OAuthAuthorizerSpy(
                callbackURL: URL(string: "pawfolio://auth/callback?code=unused")!
            )
        )

        do {
            _ = try await service.signIn(using: .apple)
            XCTFail("Expected Apple sign-in to remain unavailable")
        } catch let error as SupabaseServiceError {
            XCTAssertEqual(error, .providerUnavailable(.apple))
        }
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testExpiredSessionRefreshesAndPreservesRefreshToken() async throws {
        let store = MemorySupabaseSessionStore(
            session: storedSession(
                accessToken: "expired-access",
                refreshToken: "refresh-1",
                expiresAt: 900
            )
        )
        let transport = SupabaseTransportSpy(responses: [
            response(
                statusCode: 200,
                json: """
                {
                  "access_token": "access-2",
                  "token_type": "bearer",
                  "expires_in": 120,
                  "user": { "id": "user-1", "email": "cat@example.com" }
                }
                """
            )
        ])
        let service = SupabaseAuthenticationService(
            configuration: configuration,
            sessionStore: store,
            transport: transport,
            nowMilliseconds: { 1_000 },
            refreshLeewayMilliseconds: 0
        )

        let session = try await service.currentSession()

        XCTAssertEqual(session?.userID, "user-1")
        XCTAssertEqual(session?.displayName, "Saved Cat")
        XCTAssertEqual(session?.expiresAtMilliseconds, 121_000)
        let refreshed = try await store.load()
        XCTAssertEqual(refreshed?.accessToken, "access-2")
        XCTAssertEqual(refreshed?.refreshToken, "refresh-1")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "grant_type" })?.value, "refresh_token")
        let body = try jsonObject(from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["refresh_token"] as? String, "refresh-1")
    }

    func testCloudFetchDecodesHoldingPayloads() async throws {
        let transport = SupabaseTransportSpy(responses: [
            response(
                statusCode: 200,
                json: """
                [{
                  "payload": {
                    "schemaVersion": 2,
                    "id": "remote-1",
                    "symbol": "AAPL",
                    "holdingKind": "market",
                    "quantity": 2,
                    "costPerShare": 100,
                    "createdAt": 100
                  }
                }]
                """
            )
        ])
        let repository = SupabaseCloudHoldingRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: transport
        )

        let holdings = try await repository.fetchAll(for: "user-1")

        XCTAssertEqual(holdings.map(\.id), ["remote-1"])
        XCTAssertEqual(holdings.first?.quantity, 2)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        XCTAssertEqual(value(named: "select", in: items), "payload")
        XCTAssertEqual(value(named: "user_id", in: items), "eq.user-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }

    func testCloudUpsertUsesCompositeConflictTargetAndIncludesTombstone() async throws {
        let transport = SupabaseTransportSpy(responses: [response(statusCode: 201, json: "")])
        let repository = SupabaseCloudHoldingRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: transport
        )
        let tombstone = Holding(
            id: "deleted-1",
            symbol: "VOO",
            holdingKind: .market,
            quantity: 1,
            costPerShare: 400,
            createdAt: 100,
            updatedAt: 300,
            deletedAt: 300
        )

        try await repository.upsert([tombstone], for: "user-1")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        XCTAssertEqual(value(named: "on_conflict", in: items), "user_id,id")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Prefer"),
            "resolution=merge-duplicates,return=minimal"
        )

        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [[String: Any]]
        )
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row["id"] as? String, "deleted-1")
        XCTAssertEqual(row["user_id"] as? String, "user-1")
        let payload = try XCTUnwrap(row["payload"] as? [String: Any])
        XCTAssertEqual(payload["schemaVersion"] as? Int, Holding.currentSchemaVersion)
        XCTAssertEqual(payload["deletedAt"] as? Double, 300)
    }

    func testCloudRequestRefreshesTokenAndRetriesOnceAfter401() async throws {
        let transport = SupabaseTransportSpy(responses: [
            response(statusCode: 401, json: #"{"message":"expired"}"#),
            response(statusCode: 200, json: "[]")
        ])
        let tokenProvider = TokenProviderSpy(tokens: ["expired-access", "fresh-access"])
        let repository = SupabaseCloudHoldingRepository(
            configuration: configuration,
            tokenProvider: tokenProvider,
            transport: transport
        )

        let holdings = try await repository.fetchAll(for: "user-1")

        XCTAssertTrue(holdings.isEmpty)
        let flags = await tokenProvider.recordedForceRefreshFlags()
        XCTAssertEqual(flags, [false, true])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer expired-access")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access")
    }

    func testCloudProfileFetchDecodesSharedAvatarAndTimestamp() async throws {
        let transport = SupabaseTransportSpy(responses: [
            response(
                statusCode: 200,
                json: """
                [{
                  "display_name": "JiuJiu",
                  "avatar": "cat:jiujiu",
                  "updated_at": "2026-01-01T00:00:00.000Z"
                }]
                """
            )
        ])
        let repository = SupabaseCloudProfileRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: transport
        )

        let profile = try await repository.fetch(for: "user-1")

        XCTAssertEqual(profile?.displayName, "JiuJiu")
        XCTAssertEqual(profile?.avatar, .catJiujiu)
        XCTAssertEqual(profile?.updatedAtMilliseconds, 1_767_225_600_000)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/rest/v1/profiles")
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        XCTAssertEqual(value(named: "user_id", in: items), "eq.user-1")
        XCTAssertEqual(value(named: "limit", in: items), "1")
    }

    func testCloudProfileFetchReturnsNilForMissingRowAndRejectsUnknownAvatar() async throws {
        let missingRepository = SupabaseCloudProfileRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: SupabaseTransportSpy(responses: [response(statusCode: 200, json: "[]")])
        )
        let missing = try await missingRepository.fetch(for: "user-1")
        XCTAssertNil(missing)

        let invalidRepository = SupabaseCloudProfileRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: SupabaseTransportSpy(responses: [
                response(
                    statusCode: 200,
                    json: """
                    [{
                      "display_name": "Unknown",
                      "avatar": "remote:untrusted",
                      "updated_at": "2026-01-01T00:00:00Z"
                    }]
                    """
                )
            ])
        )

        do {
            _ = try await invalidRepository.fetch(for: "user-1")
            XCTFail("Expected the untrusted avatar identifier to be rejected")
        } catch let error as SupabaseServiceError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testCloudProfileUpsertUsesOwnerKeyAndSharedAvatarIdentifier() async throws {
        let transport = SupabaseTransportSpy(responses: [response(statusCode: 201, json: "")])
        let repository = SupabaseCloudProfileRepository(
            configuration: configuration,
            tokenProvider: TokenProviderSpy(tokens: ["access-1"]),
            transport: transport
        )
        let profile = LocalAccountProfile(
            displayName: "  Puffy  ",
            avatar: .catPuffy,
            updatedAtMilliseconds: 1_767_225_600_000
        )

        try await repository.upsert(profile, for: "user-1")

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/rest/v1/profiles")
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        XCTAssertEqual(value(named: "on_conflict", in: items), "user_id")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Prefer"),
            "resolution=merge-duplicates,return=minimal"
        )
        let body = try jsonObject(from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["user_id"] as? String, "user-1")
        XCTAssertEqual(body["display_name"] as? String, "Puffy")
        XCTAssertEqual(body["avatar"] as? String, "cat:puffy")
        XCTAssertEqual(body["updated_at"] as? String, "2026-01-01T00:00:00.000Z")
    }

    func testCloudProfileRequestRefreshesTokenAndRetriesOnceAfter401() async throws {
        let transport = SupabaseTransportSpy(responses: [
            response(statusCode: 401, json: #"{"message":"expired"}"#),
            response(statusCode: 200, json: "[]")
        ])
        let tokenProvider = TokenProviderSpy(tokens: ["expired-access", "fresh-access"])
        let repository = SupabaseCloudProfileRepository(
            configuration: configuration,
            tokenProvider: tokenProvider,
            transport: transport
        )

        _ = try await repository.fetch(for: "user-1")

        let flags = await tokenProvider.recordedForceRefreshFlags()
        XCTAssertEqual(flags, [false, true])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer expired-access")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access")
    }

    private func response(statusCode: Int, json: String) -> SupabaseHTTPResponse {
        SupabaseHTTPResponse(data: Data(json.utf8), statusCode: statusCode)
    }

    private func storedSession(
        accessToken: String,
        refreshToken: String,
        expiresAt: TimeInterval
    ) -> StoredSupabaseSession {
        StoredSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "bearer",
            expiresAtMilliseconds: expiresAt,
            userID: "user-1",
            email: "cat@example.com",
            displayName: "Saved Cat",
            provider: .google
        )
    }

    private func value(named name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor MemorySupabaseSessionStore: SupabaseSessionStoring {
    private var session: StoredSupabaseSession?

    init(session: StoredSupabaseSession? = nil) {
        self.session = session
    }

    func load() async throws -> StoredSupabaseSession? {
        session
    }

    func save(_ session: StoredSupabaseSession) async throws {
        self.session = session
    }

    func delete() async throws {
        session = nil
    }
}

@MainActor
private final class OAuthAuthorizerSpy: OAuthAuthorizationProviding {
    private let callbackURL: URL
    private(set) var authorizationURL: URL?
    private(set) var callbackURLScheme: String?

    init(callbackURL: URL) {
        self.callbackURL = callbackURL
    }

    func authenticate(at authorizationURL: URL, callbackURLScheme: String) async throws -> URL {
        self.authorizationURL = authorizationURL
        self.callbackURLScheme = callbackURLScheme
        return callbackURL
    }
}

private actor SupabaseTransportSpy: SupabaseHTTPTransporting {
    private var responses: [SupabaseHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [SupabaseHTTPResponse] = []) {
        self.responses = responses
    }

    func response(for request: URLRequest) async throws -> SupabaseHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw SupabaseTestError.missingResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor TokenProviderSpy: SupabaseAccessTokenProviding {
    private var tokens: [String]
    private var forceRefreshFlags: [Bool] = []

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        forceRefreshFlags.append(forceRefresh)
        guard !tokens.isEmpty else { throw SupabaseTestError.missingToken }
        return tokens.removeFirst()
    }

    func recordedForceRefreshFlags() -> [Bool] {
        forceRefreshFlags
    }
}

private enum SupabaseTestError: Error {
    case missingResponse
    case missingToken
}
