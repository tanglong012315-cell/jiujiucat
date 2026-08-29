import Foundation

enum HoldingKind: String, CaseIterable, Codable, Sendable {
    case market
    case interest
    case hybrid
    case dividend
}

enum AssetType: String, CaseIterable, Codable, Sendable {
    case equity = "EQUITY"
    case etf = "ETF"
    case cryptocurrency = "CRYPTOCURRENCY"
    case stable = "STABLE"
}

enum PositionAdjustmentKind: String, Codable, Hashable, Sendable {
    case add
    case reduce
}

enum DividendFrequency: String, CaseIterable, Codable, Sendable {
    case quarterly
    case monthly
    case semimonthly
    case semiannual
    case annual
    case irregular
}

struct PositionAdjustment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let type: PositionAdjustmentKind
    let quantity: Double
    let price: Double
    let createdAt: TimeInterval
}

struct PrincipalAdjustment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let type: PositionAdjustmentKind
    let amount: Double
    let date: String
    let at: TimeInterval?
    let createdAt: TimeInterval

    init(
        id: String,
        type: PositionAdjustmentKind,
        amount: Double,
        date: String,
        at: TimeInterval? = nil,
        createdAt: TimeInterval
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.at = at
        self.createdAt = createdAt
    }
}

struct DividendRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var perShare: Double
    var quantity: Double
    var amount: Double
    var frequency: DividendFrequency
    var exDate: String
    var payDate: String
    let createdAt: TimeInterval
}

struct Holding: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var id: String
    var symbol: String
    var quoteSymbol: String
    var name: String
    var assetType: AssetType?
    var exchange: String
    var holdingKind: HoldingKind
    var quantity: Double?
    var costPerShare: Double?
    var priceOverride: Double?
    var principal: Double?
    var annualRate: Double?
    var interestMode: InterestMode?
    var interestStartDate: String?
    var dividendPerShare: Double?
    var dividendFrequency: DividendFrequency?
    var dividendExDate: String?
    var dividendPayDate: String?
    var positionAdjustments: [PositionAdjustment]
    var principalAdjustments: [PrincipalAdjustment]
    var interestSkips: [String]
    var dividendRecords: [DividendRecord]
    var dividendRecordId: String?
    /// 用户备注，最多 20 字。空备注一律存 nil，不存空串——空串会让「有没有备注」
    /// 在两端出现两种判法。截断在 `Holding.normalizedNote` 里做。
    var note: String?
    var createdAt: TimeInterval
    var updatedAt: TimeInterval?
    var closedAt: TimeInterval?
    var deletedAt: TimeInterval?

    init(
        schemaVersion: Int = Holding.currentSchemaVersion,
        id: String,
        symbol: String,
        quoteSymbol: String? = nil,
        name: String? = nil,
        assetType: AssetType? = nil,
        exchange: String = "",
        holdingKind: HoldingKind,
        quantity: Double? = nil,
        costPerShare: Double? = nil,
        priceOverride: Double? = nil,
        principal: Double? = nil,
        annualRate: Double? = nil,
        interestMode: InterestMode? = nil,
        interestStartDate: String? = nil,
        dividendPerShare: Double? = nil,
        dividendFrequency: DividendFrequency? = nil,
        dividendExDate: String? = nil,
        dividendPayDate: String? = nil,
        positionAdjustments: [PositionAdjustment] = [],
        principalAdjustments: [PrincipalAdjustment] = [],
        interestSkips: [String] = [],
        dividendRecords: [DividendRecord] = [],
        dividendRecordId: String? = nil,
        note: String? = nil,
        createdAt: TimeInterval,
        updatedAt: TimeInterval? = nil,
        closedAt: TimeInterval? = nil,
        deletedAt: TimeInterval? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.symbol = symbol
        self.quoteSymbol = quoteSymbol ?? symbol
        self.name = name ?? symbol
        self.assetType = assetType
        self.exchange = exchange
        self.holdingKind = holdingKind
        self.quantity = quantity
        self.costPerShare = costPerShare
        self.priceOverride = priceOverride
        self.principal = principal
        self.annualRate = annualRate
        self.interestMode = interestMode
        self.interestStartDate = interestStartDate
        self.dividendPerShare = dividendPerShare
        self.dividendFrequency = dividendFrequency
        self.dividendExDate = dividendExDate
        self.dividendPayDate = dividendPayDate
        self.positionAdjustments = positionAdjustments
        self.principalAdjustments = principalAdjustments
        self.interestSkips = interestSkips
        self.dividendRecords = dividendRecords
        self.dividendRecordId = dividendRecordId
        self.note = Holding.normalizedNote(note)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.deletedAt = deletedAt
    }

    /// 备注的统一口径：去首尾空白，最多 20 个字符，空的算没有。
    ///
    /// 数的是 `Character`，不是 UTF-16 —— 中文和 emoji 都按一个字算，和 Web 那边
    /// `[...text].length` 的计法一致；`String.count` 换成 `utf16.count` 会让同一条备注
    /// 在两端裁出不同长度。
    static func normalizedNote(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return String(trimmed.prefix(noteCharacterLimit))
    }

    static let noteCharacterLimit = 20

    var isClosed: Bool {
        closedAt != nil
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var isInterestBearing: Bool {
        holdingKind == .interest || holdingKind == .hybrid
    }

    var currentCostBasis: Double {
        switch holdingKind {
        case .interest:
            max(0, principal ?? 0)
        case .market, .hybrid, .dividend:
            max(0, quantity ?? 0) * max(0, costPerShare ?? 0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case symbol
        case quoteSymbol
        case name
        case assetType
        case exchange
        case holdingKind
        case quantity
        case costPerShare
        case priceOverride
        case principal
        case annualRate
        case interestMode
        case interestStartDate
        case dividendPerShare
        case dividendFrequency
        case dividendExDate
        case dividendPayDate
        case positionAdjustments
        case principalAdjustments
        case interestSkips
        case dividendRecords
        case dividendRecordId
        case note
        case createdAt
        case updatedAt
        case closedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        quoteSymbol = try container.decodeIfPresent(String.self, forKey: .quoteSymbol) ?? symbol
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? quoteSymbol

        let assetTypeValue = try container.decodeIfPresent(String.self, forKey: .assetType)
        assetType = assetTypeValue.flatMap(AssetType.init(rawValue:))
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange) ?? ""

        let holdingKindValue = try container.decodeIfPresent(String.self, forKey: .holdingKind)
        holdingKind = holdingKindValue.flatMap(HoldingKind.init(rawValue:)) ?? .market

        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        costPerShare = try container.decodeIfPresent(Double.self, forKey: .costPerShare)
        priceOverride = try container.decodeIfPresent(Double.self, forKey: .priceOverride)
        principal = try container.decodeIfPresent(Double.self, forKey: .principal)
        annualRate = try container.decodeIfPresent(Double.self, forKey: .annualRate)

        let interestModeValue = try container.decodeIfPresent(String.self, forKey: .interestMode)
        interestMode = interestModeValue.flatMap(InterestMode.init(rawValue:))
        if (holdingKind == .interest || holdingKind == .hybrid), interestMode == nil {
            interestMode = .simple
        }
        interestStartDate = try container.decodeIfPresent(String.self, forKey: .interestStartDate)
        dividendPerShare = try container.decodeIfPresent(Double.self, forKey: .dividendPerShare)

        let dividendFrequencyValue = try container.decodeIfPresent(String.self, forKey: .dividendFrequency)
        dividendFrequency = dividendFrequencyValue.flatMap(DividendFrequency.init(rawValue:))
        dividendExDate = try container.decodeIfPresent(String.self, forKey: .dividendExDate)
        dividendPayDate = try container.decodeIfPresent(String.self, forKey: .dividendPayDate)

        positionAdjustments = try container.decodeIfPresent([PositionAdjustment].self, forKey: .positionAdjustments) ?? []
        principalAdjustments = try container.decodeIfPresent([PrincipalAdjustment].self, forKey: .principalAdjustments) ?? []
        interestSkips = try container.decodeIfPresent([String].self, forKey: .interestSkips) ?? []
        dividendRecords = try container.decodeIfPresent([DividendRecord].self, forKey: .dividendRecords) ?? []
        dividendRecordId = try container.decodeIfPresent(String.self, forKey: .dividendRecordId)
        // 云端和 Web 都可能写进更长的备注（比如有人绕过表单直接改数据）。
        // 读进来就按同一把尺子裁掉，免得原生这边显示出一条 Web 上看不全的备注。
        note = Holding.normalizedNote(try container.decodeIfPresent(String.self, forKey: .note))
        createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? 0
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt)
        closedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .closedAt)
        deletedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .deletedAt)
    }
}
