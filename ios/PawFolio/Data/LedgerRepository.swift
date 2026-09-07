import Foundation

struct LedgerStoreSnapshot: Codable, Equatable, Sendable {
    static let currentStorageVersion = 1

    var storageVersion: Int = currentStorageVersion
    var ledgerSchemaVersion: Int = LedgerEntry.currentSchemaVersion
    var legacyMigrationVersion: Int?
    var entries: [LedgerEntry] = []
    var earnProducts: [EarnProduct] = []
}

protocol ScopedLedgerRepository: Sendable {
    func load(for scope: HoldingStorageScope) async throws -> LedgerStoreSnapshot
    func save(_ snapshot: LedgerStoreSnapshot, for scope: HoldingStorageScope) async throws
}

actor ScopedLocalLedgerRepository: ScopedLedgerRepository {
    private let baseDirectoryURL: URL

    init(baseDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL ?? Self.defaultBaseDirectoryURL()
    }

    func load(for scope: HoldingStorageScope) async throws -> LedgerStoreSnapshot {
        let url = try fileURL(for: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return LedgerStoreSnapshot() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LedgerStoreSnapshot.self, from: Data(contentsOf: url))
            guard snapshot.storageVersion == LedgerStoreSnapshot.currentStorageVersion,
                  snapshot.ledgerSchemaVersion == LedgerEntry.currentSchemaVersion else {
                throw LedgerRepositoryError.unsupportedVersion
            }
            try snapshot.earnProducts.forEach { try $0.validate() }
            _ = try LedgerProjection(entries: snapshot.entries)
            return snapshot
        } catch let error as LedgerRepositoryError {
            throw error
        } catch {
            throw LedgerRepositoryError.unreadableData
        }
    }

    func save(_ snapshot: LedgerStoreSnapshot, for scope: HoldingStorageScope) async throws {
        guard snapshot.storageVersion == LedgerStoreSnapshot.currentStorageVersion,
              snapshot.ledgerSchemaVersion == LedgerEntry.currentSchemaVersion else {
            throw LedgerRepositoryError.unsupportedVersion
        }
        try snapshot.earnProducts.forEach { try $0.validate() }
        _ = try LedgerProjection(entries: snapshot.entries)
        let url = try fileURL(for: scope)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: [.atomic])
        } catch let error as LedgerError {
            throw error
        } catch {
            throw LedgerRepositoryError.unavailableDirectory
        }
    }

    private func fileURL(for scope: HoldingStorageScope) throws -> URL {
        switch scope {
        case .guest:
            return baseDirectoryURL.appendingPathComponent("ledger-v3.json")
        case let .account(userID):
            let value = userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 256 else {
                throw LedgerRepositoryError.invalidAccountIdentifier
            }
            let encoded = Data(value.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return baseDirectoryURL
                .appendingPathComponent("Accounts", isDirectory: true)
                .appendingPathComponent("account-\(encoded)", isDirectory: true)
                .appendingPathComponent("ledger-v3.json")
        }
    }

    private static func defaultBaseDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PawFolio", isDirectory: true)
    }
}

enum LedgerRepositoryError: LocalizedError, Equatable {
    case unreadableData
    case unavailableDirectory
    case invalidAccountIdentifier
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .unreadableData: "The local transaction ledger could not be read."
        case .unavailableDirectory: "The local transaction ledger could not be saved."
        case .invalidAccountIdentifier: "The account identifier is invalid."
        case .unsupportedVersion: "This transaction ledger version is not supported."
        }
    }
}
