import AuthenticationServices
import UIKit

@MainActor
final class SystemOAuthAuthorizer: NSObject, OAuthAuthorizationProviding {
    private var activeSession: ASWebAuthenticationSession?

    func authenticate(
        at authorizationURL: URL,
        callbackURLScheme: String
    ) async throws -> URL {
        guard activeSession == nil else {
            throw SupabaseServiceError.oauthAlreadyInProgress
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: callbackURLScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.activeSession = nil

                        if let callbackURL {
                            continuation.resume(returning: callbackURL)
                        } else if let authenticationError = error as? ASWebAuthenticationSessionError,
                                  authenticationError.code == .canceledLogin {
                            continuation.resume(throwing: CancellationError())
                        } else if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: SupabaseServiceError.oauthCallbackInvalid)
                        }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                activeSession = session

                guard session.start() else {
                    activeSession = nil
                    continuation.resume(throwing: SupabaseServiceError.oauthCallbackInvalid)
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.activeSession?.cancel()
            }
        }
    }
}

extension SystemOAuthAuthorizer: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        if let keyWindow = foregroundScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }

        if let visibleWindow = foregroundScenes
            .flatMap(\.windows)
            .first(where: { !$0.isHidden }) {
            return visibleWindow
        }

        return ASPresentationAnchor()
    }
}
