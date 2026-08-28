import Foundation

enum GuestImportDecision: String, Codable, Equatable, Sendable {
    case keepSeparate
    case copiedIntoAccount
}

protocol GuestImportDecisionStoring: Sendable {
    func decision(for userID: String) async throws -> GuestImportDecision?
    func save(_ decision: GuestImportDecision, for userID: String) async throws
}

enum GuestImportDecisionStoreError: LocalizedError {
    case invalidUserIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidUserIdentifier:
            "账号标识无效，无法保存游客数据选择。"
        }
    }
}

actor UserDefaultsGuestImportDecisionStore: GuestImportDecisionStoring {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        suiteName: String? = nil,
        storageKey: String = "PawFolio.guestImportDecisions.v1"
    ) {
        if let suiteName, let suiteDefaults = UserDefaults(suiteName: suiteName) {
            defaults = suiteDefaults
        } else {
            defaults = .standard
        }
        self.storageKey = storageKey
    }

    func decision(for userID: String) async throws -> GuestImportDecision? {
        let key = try normalizedUserID(userID)
        guard let rawValue = storedDecisions()[key] else { return nil }
        return GuestImportDecision(rawValue: rawValue)
    }

    func save(_ decision: GuestImportDecision, for userID: String) async throws {
        let key = try normalizedUserID(userID)
        var decisions = storedDecisions()
        decisions[key] = decision.rawValue
        defaults.set(decisions, forKey: storageKey)
    }

    private func storedDecisions() -> [String: String] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? String else { return }
            result[entry.key] = value
        } ?? [:]
    }

    private func normalizedUserID(_ userID: String) throws -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 256 else {
            throw GuestImportDecisionStoreError.invalidUserIdentifier
        }
        return normalized
    }
}
