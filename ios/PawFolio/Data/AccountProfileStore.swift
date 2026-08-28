import Foundation

enum CatAvatar: String, CaseIterable, Codable, Equatable, Sendable {
    case faceHappy = "face:happy"
    case faceCute = "face:cute"
    case faceLove = "face:love"
    case faceThinking = "face:thinking"
    case faceSleepy = "face:sleepy"
    case faceSurprised = "face:surprised"
    case faceCrying = "face:crying"
    case faceAngry = "face:angry"
    case faceHorn = "face:horn"
    case catPuffy = "cat:puffy"
    case catNono = "cat:nono"
    case catJiujiu = "cat:jiujiu"
    case catLiz = "cat:liz"
    case catPudding = "cat:pudding"
    case catZhezhe = "cat:zhezhe"
    case catCoco = "cat:coco"
    case catMomo = "cat:momo"
    case catBobo = "cat:bobo"

    static let faceOptions: [Self] = [
        .faceHappy, .faceCute, .faceLove,
        .faceThinking, .faceSleepy, .faceSurprised,
        .faceCrying, .faceAngry, .faceHorn
    ]

    static let catOptions: [Self] = [
        .catPuffy, .catNono, .catJiujiu,
        .catLiz, .catPudding, .catZhezhe,
        .catCoco, .catMomo, .catBobo
    ]

    static func decodePersisted(_ rawValue: String?) -> Self {
        guard let rawValue else { return .faceHappy }
        if let sharedValue = Self(rawValue: rawValue) {
            return sharedValue
        }
        return switch rawValue {
        case "snow": .faceCute
        case "pawBlue": .faceHappy
        case "ginger": .faceLove
        case "lilac": .faceThinking
        case "mocha": .faceSleepy
        case "midnight": .faceHorn
        default: .faceHappy
        }
    }
}

struct LocalAccountProfile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let displayName: String?
    let avatar: CatAvatar
    let updatedAtMilliseconds: TimeInterval

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        displayName: String? = nil,
        avatar: CatAvatar = .faceHappy,
        updatedAtMilliseconds: TimeInterval = 0
    ) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        self.displayName = displayName
        self.avatar = avatar
        self.updatedAtMilliseconds = updatedAtMilliseconds.isFinite
            ? max(0, updatedAtMilliseconds)
            : 0
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case displayName
        case avatar
        case updatedAtMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = max(
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            Self.currentSchemaVersion
        )
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let avatarValue = try container.decodeIfPresent(String.self, forKey: .avatar)
        avatar = CatAvatar.decodePersisted(avatarValue)
        let decodedTimestamp = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .updatedAtMilliseconds
        ) ?? 0
        updatedAtMilliseconds = decodedTimestamp.isFinite ? max(0, decodedTimestamp) : 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(avatar.rawValue, forKey: .avatar)
        try container.encode(updatedAtMilliseconds, forKey: .updatedAtMilliseconds)
    }
}

protocol AccountProfileStoring: Sendable {
    func profile(for userID: String) async throws -> LocalAccountProfile?
    func save(_ profile: LocalAccountProfile, for userID: String) async throws
}

protocol CloudProfileRepository: Sendable {
    func fetch(for userID: String) async throws -> LocalAccountProfile?
    func upsert(_ profile: LocalAccountProfile, for userID: String) async throws
}

struct AccountProfileMergeResult: Equatable, Sendable {
    let profile: LocalAccountProfile
    let shouldSaveLocally: Bool
    let shouldUploadRemotely: Bool
}

enum AccountProfileMerge {
    static func reconcile(
        local: LocalAccountProfile?,
        remote: LocalAccountProfile?
    ) -> AccountProfileMergeResult? {
        switch (local, remote) {
        case (nil, nil):
            nil
        case let (local?, nil):
            AccountProfileMergeResult(
                profile: local,
                shouldSaveLocally: false,
                shouldUploadRemotely: local.updatedAtMilliseconds > 0
            )
        case let (nil, remote?):
            AccountProfileMergeResult(
                profile: remote,
                shouldSaveLocally: true,
                shouldUploadRemotely: false
            )
        case let (local?, remote?):
            if remote.updatedAtMilliseconds > local.updatedAtMilliseconds {
                AccountProfileMergeResult(
                    profile: remote,
                    shouldSaveLocally: remote != local,
                    shouldUploadRemotely: false
                )
            } else {
                AccountProfileMergeResult(
                    profile: local,
                    shouldSaveLocally: false,
                    shouldUploadRemotely: local != remote
                )
            }
        }
    }
}

enum AccountProfileStoreError: LocalizedError, Equatable {
    case invalidUserIdentifier
    case invalidDisplayName
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .invalidUserIdentifier:
            "账号标识无效，无法保存个人资料。"
        case .invalidDisplayName:
            "显示名称最多可输入 20 个字符。"
        case .invalidStoredData:
            "本机个人资料无法读取，请重新选择头像。"
        }
    }
}

actor UserDefaultsAccountProfileStore: AccountProfileStoring {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        suiteName: String? = nil,
        storageKey: String = "PawFolio.accountProfiles.v1"
    ) {
        if let suiteName, let suiteDefaults = UserDefaults(suiteName: suiteName) {
            defaults = suiteDefaults
        } else {
            defaults = .standard
        }
        self.storageKey = storageKey
    }

    func profile(for userID: String) async throws -> LocalAccountProfile? {
        let key = try normalizedUserID(userID)
        return try storedProfiles()[key]
    }

    func save(_ profile: LocalAccountProfile, for userID: String) async throws {
        let key = try normalizedUserID(userID)
        let normalizedName = profile.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName?.count ?? 0 <= 20 else {
            throw AccountProfileStoreError.invalidDisplayName
        }

        let normalizedProfile = LocalAccountProfile(
            displayName: normalizedName?.isEmpty == false ? normalizedName : nil,
            avatar: profile.avatar,
            updatedAtMilliseconds: profile.updatedAtMilliseconds
        )
        var profiles = try storedProfiles()
        profiles[key] = normalizedProfile
        defaults.set(try JSONEncoder().encode(profiles), forKey: storageKey)
    }

    private func storedProfiles() throws -> [String: LocalAccountProfile] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: LocalAccountProfile].self, from: data)
        } catch {
            throw AccountProfileStoreError.invalidStoredData
        }
    }

    private func normalizedUserID(_ userID: String) throws -> String {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 256 else {
            throw AccountProfileStoreError.invalidUserIdentifier
        }
        return normalized
    }
}
