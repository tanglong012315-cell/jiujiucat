import Foundation

protocol HoldingRepository: Sendable {
    func load() async throws -> [Holding]
    func save(_ holdings: [Holding]) async throws
}

enum HoldingStorageScope: Hashable, Sendable {
    case guest
    case account(userID: String)
}

protocol ScopedHoldingRepository: Sendable {
    func load(for scope: HoldingStorageScope) async throws -> [Holding]
    func save(_ holdings: [Holding], for scope: HoldingStorageScope) async throws
}

actor FixedScopeHoldingRepository: HoldingRepository {
    private let repository: any ScopedHoldingRepository
    private let scope: HoldingStorageScope

    init(
        repository: any ScopedHoldingRepository,
        scope: HoldingStorageScope
    ) {
        self.repository = repository
        self.scope = scope
    }

    func load() async throws -> [Holding] {
        return try await repository.load(for: scope)
    }

    func save(_ holdings: [Holding]) async throws {
        try await repository.save(holdings, for: scope)
    }
}

enum HoldingRepositoryError: LocalizedError {
    case unreadableData
    case unavailableDirectory
    case invalidAccountIdentifier

    var errorDescription: String? {
        switch self {
        case .unreadableData:
            "本地持仓文件无法读取。原文件已保留，请稍后重试。"
        case .unavailableDirectory:
            "无法创建本地数据目录。"
        case .invalidAccountIdentifier:
            "账号标识无效，无法打开对应的本地持仓。"
        }
    }
}

actor LocalHoldingRepository: HoldingRepository {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() async throws -> [Holding] {
        try HoldingFileStore.load(from: fileURL)
    }

    func save(_ holdings: [Holding]) async throws {
        try HoldingFileStore.save(holdings, to: fileURL)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("PawFolio", isDirectory: true)
            .appendingPathComponent("holdings-v1.json", isDirectory: false)
    }
}

actor ScopedLocalHoldingRepository: ScopedHoldingRepository {
    private let baseDirectoryURL: URL

    init(baseDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL ?? Self.defaultBaseDirectoryURL()
    }

    func load(for scope: HoldingStorageScope) async throws -> [Holding] {
        try HoldingFileStore.load(from: fileURL(for: scope))
    }

    func save(_ holdings: [Holding], for scope: HoldingStorageScope) async throws {
        try HoldingFileStore.save(holdings, to: fileURL(for: scope))
    }

    private func fileURL(for scope: HoldingStorageScope) throws -> URL {
        switch scope {
        case .guest:
            // Keep the original path so upgrading the app never strands guest data.
            return baseDirectoryURL.appendingPathComponent("holdings-v1.json", isDirectory: false)
        case let .account(userID):
            let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.utf8.count <= 256 else {
                throw HoldingRepositoryError.invalidAccountIdentifier
            }
            let encoded = Data(normalized.utf8)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return baseDirectoryURL
                .appendingPathComponent("Accounts", isDirectory: true)
                .appendingPathComponent("account-\(encoded)", isDirectory: true)
                .appendingPathComponent("holdings-v1.json", isDirectory: false)
        }
    }

    private static func defaultBaseDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("PawFolio", isDirectory: true)
    }
}

private enum HoldingFileStore {
    private struct Envelope: Codable {
        static let currentStorageVersion = 1

        let storageVersion: Int
        let holdings: [Holding]
    }

    static func load(from fileURL: URL) throws -> [Holding] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope.holdings
        }

        // Early development builds stored a bare array. Keep this fallback so
        // those local records survive the storage envelope migration.
        if let legacyHoldings = try? decoder.decode([Holding].self, from: data) {
            return legacyHoldings
        }

        throw HoldingRepositoryError.unreadableData
    }

    static func save(_ holdings: [Holding], to fileURL: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw HoldingRepositoryError.unavailableDirectory
        }

        let envelope = Envelope(
            storageVersion: Envelope.currentStorageVersion,
            holdings: holdings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: fileURL, options: [.atomic])
    }
}
