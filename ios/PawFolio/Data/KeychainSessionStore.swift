import Foundation
import Security

enum KeychainSessionStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "无法访问安全登录信息（Keychain 状态：\(status)）。"
        case .invalidStoredData:
            "安全登录信息已损坏，请重新登录。"
        }
    }
}

actor KeychainSupabaseSessionStore: SupabaseSessionStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.jiujiucat.pawfolio.supabase-session",
        account: String = "current"
    ) {
        self.service = service
        self.account = account
    }

    func load() async throws -> StoredSupabaseSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainSessionStoreError.invalidStoredData
        }
        do {
            return try JSONDecoder().decode(StoredSupabaseSession.self, from: data)
        } catch {
            throw KeychainSessionStoreError.invalidStoredData
        }
    }

    func save(_ session: StoredSupabaseSession) async throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(updateStatus)
        }

        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(insertStatus)
        }
    }

    func delete() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }
}
