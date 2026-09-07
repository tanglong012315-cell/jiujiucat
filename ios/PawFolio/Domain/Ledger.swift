import Foundation

/// V2.1.0 账本中的资产。资产代码是账本计量单位，不在账本层做汇率换算。
struct LedgerAsset: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fiat
        case stablecoin
        case cryptocurrency
        case equity
        case etf
    }

    let code: String
    let kind: Kind

    init(code: String, kind: Kind) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.kind = kind
    }

    var canEnterEarn: Bool {
        kind == .fiat || kind == .stablecoin || kind == .cryptocurrency
    }
}

enum LedgerAccountKind: String, Codable, Sendable {
    case fiat
    case trading
    case earn
    case external
}

/// `identifier` 让同一类账户可以并存：例如 Bank、Cash、Exchange 以及不同 Earn 产品。
struct LedgerAccountReference: Codable, Hashable, Sendable {
    let kind: LedgerAccountKind
    let identifier: String

    static func fiat(_ location: String) -> Self {
        Self(kind: .fiat, identifier: normalized(location, fallback: "exchange"))
    }

    static let trading = Self(kind: .trading, identifier: "exchange")

    static func earn(productID: String) -> Self {
        Self(kind: .earn, identifier: normalized(productID, fallback: "unknown-product"))
    }

    static func external(_ identifier: String) -> Self {
        Self(kind: .external, identifier: normalized(identifier, fallback: "external"))
    }

    var isUserControlled: Bool { kind != .external }

    private static func normalized(_ value: String, fallback: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? fallback : normalized
    }
}

struct LedgerPosting: Codable, Equatable, Sendable {
    let account: LedgerAccountReference
    let asset: LedgerAsset
    /// 正数流入账户，负数流出账户。
    let quantity: Double
}

enum LedgerEntryKind: String, Codable, Sendable {
    case deposit
    case expense
    case buy
    case sell
    case earnSubscribe
    case earnRedeem
    case interest
    case openingBalance
    case reversal
}

struct LedgerTradeDetails: Codable, Equatable, Sendable {
    let unitPrice: Double
    let settlementAsset: LedgerAsset
    let fee: Double
}

extension LedgerTradeDetails {
    /// 手续费的口径（用户 2026-09-05）：用户填的是**费率**，账本里存的是
    /// 「成交额 × 费率」算出来的绝对额，绝对额只用于展示和记账。
    /// 费率非法（负数/非有限）时返回 nil，由调用方拦下。
    static func feeAmount(grossValue: Double, ratePercent: Double) -> Double? {
        guard grossValue.isFinite, grossValue >= 0,
              ratePercent.isFinite, ratePercent >= 0 else { return nil }
        return grossValue * ratePercent / 100
    }
}

struct LedgerEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 3
    static let balanceTolerance = 1e-9
    static let allowedSettlementCodes: Set<String> = ["USD", "USDT", "USDC"]
    /// 用户 2026-09-06 指定：交易表单的 Investment / Price 结算币默认使用 USDT。
    static let defaultSettlementCode = "USDT"

    let schemaVersion: Int
    let id: String
    let kind: LedgerEntryKind
    let occurredAt: Date
    let postings: [LedgerPosting]
    let trade: LedgerTradeDetails?
    /// 旧交易持仓迁移时保留的单位成本；期初余额不伪装成一笔历史买入。
    let openingUnitCost: Double?
    let earnProductID: String?
    let note: String?
    let reversesEntryID: String?

    /// The user-facing side of the transaction. A journal entry can touch two
    /// user-controlled accounts (for example Buy moves settlement cash out of
    /// Spot and the purchased asset into Trading), so simply taking the first
    /// posting produces the wrong amount and sign in transaction history.
    var primaryUserPosting: LedgerPosting? {
        switch kind {
        case .deposit, .openingBalance:
            return postings.first { $0.account.isUserControlled && $0.quantity > 0 }
        case .expense:
            return postings.first { $0.account.isUserControlled && $0.quantity < 0 }
        case .buy:
            guard let settlementAsset = trade?.settlementAsset else { return nil }
            return postings.first {
                $0.account == .fiat("exchange")
                    && $0.asset == settlementAsset
                    && $0.quantity < 0
            }
        case .sell:
            guard let settlementAsset = trade?.settlementAsset else { return nil }
            return postings.first {
                $0.account == .fiat("exchange")
                    && $0.asset == settlementAsset
                    && $0.quantity > 0
            }
        case .earnSubscribe:
            return postings.first { $0.account.kind != .earn && $0.account.isUserControlled && $0.quantity < 0 }
        case .earnRedeem:
            return postings.first { $0.account.kind != .earn && $0.account.isUserControlled && $0.quantity > 0 }
        case .interest:
            return postings.first { $0.account.isUserControlled && $0.quantity > 0 }
        case .reversal:
            return postings.first { $0.account.isUserControlled }
        }
    }

    init(
        schemaVersion: Int = LedgerEntry.currentSchemaVersion,
        id: String = UUID().uuidString,
        kind: LedgerEntryKind,
        occurredAt: Date,
        postings: [LedgerPosting],
        trade: LedgerTradeDetails? = nil,
        openingUnitCost: Double? = nil,
        earnProductID: String? = nil,
        note: String? = nil,
        reversesEntryID: String? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.postings = postings
        self.trade = trade
        self.openingUnitCost = openingUnitCost
        self.earnProductID = earnProductID
        self.note = Self.normalizedNote(note)
        self.reversesEntryID = reversesEntryID
        try validate()
    }

    static func deposit(
        asset: LedgerAsset,
        quantity: Double,
        into location: String = "exchange",
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try positive(quantity)
        try validateSpotAsset(asset)
        return try Self(
            id: id,
            kind: .deposit,
            occurredAt: occurredAt,
            postings: transfer(
                asset: asset,
                quantity: quantity,
                from: .external("deposit"),
                to: .fiat(location)
            ),
            note: note
        )
    }

    static func expense(
        asset: LedgerAsset,
        quantity: Double,
        from location: String,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try positive(quantity)
        try validateSpotAsset(asset)
        return try Self(
            id: id,
            kind: .expense,
            occurredAt: occurredAt,
            postings: transfer(
                asset: asset,
                quantity: quantity,
                from: .fiat(location),
                to: .external("expense")
            ),
            note: note
        )
    }

    static func buy(
        asset: LedgerAsset,
        quantity: Double,
        unitPrice: Double,
        settlementAsset: LedgerAsset,
        fee: Double = 0,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try validateTrade(asset: asset, quantity: quantity, unitPrice: unitPrice, settlementAsset: settlementAsset, fee: fee)
        let settlementQuantity = quantity * unitPrice + fee
        return try Self(
            id: id,
            kind: .buy,
            occurredAt: occurredAt,
            postings: transfer(asset: asset, quantity: quantity, from: .external("market"), to: .trading)
                + transfer(asset: settlementAsset, quantity: settlementQuantity, from: .fiat("exchange"), to: .external("market")),
            trade: LedgerTradeDetails(unitPrice: unitPrice, settlementAsset: settlementAsset, fee: fee),
            note: note
        )
    }

    static func sell(
        asset: LedgerAsset,
        quantity: Double,
        unitPrice: Double,
        settlementAsset: LedgerAsset,
        fee: Double = 0,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try validateTrade(asset: asset, quantity: quantity, unitPrice: unitPrice, settlementAsset: settlementAsset, fee: fee)
        let proceeds = quantity * unitPrice - fee
        guard proceeds > 0 else { throw LedgerError.invalidFee }
        return try Self(
            id: id,
            kind: .sell,
            occurredAt: occurredAt,
            postings: transfer(asset: asset, quantity: quantity, from: .trading, to: .external("market"))
                + transfer(asset: settlementAsset, quantity: proceeds, from: .external("market"), to: .fiat("exchange")),
            trade: LedgerTradeDetails(unitPrice: unitPrice, settlementAsset: settlementAsset, fee: fee),
            note: note
        )
    }

    static func earnSubscribe(
        product: EarnProduct,
        quantity: Double,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try positive(quantity)
        let source = try product.fundingAccount
        return try Self(
            id: id,
            kind: .earnSubscribe,
            occurredAt: occurredAt,
            postings: transfer(asset: product.asset, quantity: quantity, from: source, to: .earn(productID: product.id)),
            earnProductID: product.id,
            note: note
        )
    }

    static func earnRedeem(
        product: EarnProduct,
        quantity: Double,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        try positive(quantity)
        let destination = try product.fundingAccount
        return try Self(
            id: id,
            kind: .earnRedeem,
            occurredAt: occurredAt,
            postings: transfer(asset: product.asset, quantity: quantity, from: .earn(productID: product.id), to: destination),
            earnProductID: product.id,
            note: note
        )
    }

    /// 只有真实派息时才生成。复利进入 Earn 本金，单利进入该资产的现货账户。
    static func interestPayout(
        product: EarnProduct,
        quantity: Double,
        occurredAt: Date,
        id: String = UUID().uuidString
    ) throws -> Self {
        try positive(quantity)
        let destination: LedgerAccountReference = product.interestMode == .compound
            ? .earn(productID: product.id)
            : try product.fundingAccount
        return try Self(
            id: id,
            kind: .interest,
            occurredAt: occurredAt,
            postings: transfer(asset: product.asset, quantity: quantity, from: .external("interest"), to: destination),
            earnProductID: product.id
        )
    }

    static func openingBalance(
        asset: LedgerAsset,
        quantity: Double,
        account: LedgerAccountReference,
        occurredAt: Date,
        legacyHoldingID: String,
        unitCost: Double? = nil,
        id: String
    ) throws -> Self {
        try positive(quantity)
        guard account.isUserControlled else { throw LedgerError.invalidAccount }
        return try Self(
            id: id,
            kind: .openingBalance,
            occurredAt: occurredAt,
            postings: transfer(asset: asset, quantity: quantity, from: .external("legacy-opening"), to: account),
            openingUnitCost: unitCost,
            note: "Migrated from \(legacyHoldingID)"
        )
    }

    /// 流水不可删除。撤销通过一条金额完全相反的新流水完成，原记录永久保留。
    static func reversal(
        of entry: LedgerEntry,
        occurredAt: Date,
        note: String? = nil,
        id: String = UUID().uuidString
    ) throws -> Self {
        guard entry.kind != .reversal else { throw LedgerError.invalidReversal }
        return try Self(
            id: id,
            kind: .reversal,
            occurredAt: occurredAt,
            postings: entry.postings.map {
                LedgerPosting(account: $0.account, asset: $0.asset, quantity: -$0.quantity)
            },
            trade: entry.trade,
            openingUnitCost: nil,
            earnProductID: entry.earnProductID,
            note: note,
            reversesEntryID: entry.id
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw LedgerError.unsupportedSchemaVersion }
        guard !postings.isEmpty else { throw LedgerError.emptyEntry }
        for posting in postings {
            guard !posting.asset.code.isEmpty,
                  posting.quantity.isFinite,
                  abs(posting.quantity) > Self.balanceTolerance else {
                throw LedgerError.invalidQuantity
            }
        }
        let totals = Dictionary(grouping: postings, by: \.asset).mapValues {
            $0.reduce(0) { $0 + $1.quantity }
        }
        guard totals.values.allSatisfy({ abs($0) <= Self.balanceTolerance }) else {
            throw LedgerError.unbalancedEntry
        }
        if let openingUnitCost {
            guard kind == .openingBalance, openingUnitCost.isFinite, openingUnitCost >= 0 else {
                throw LedgerError.invalidPrice
            }
        }
        if kind == .reversal {
            guard let reversesEntryID, !reversesEntryID.isEmpty else {
                throw LedgerError.invalidReversal
            }
        } else if reversesEntryID != nil {
            throw LedgerError.invalidReversal
        }
    }

    private static func transfer(
        asset: LedgerAsset,
        quantity: Double,
        from source: LedgerAccountReference,
        to destination: LedgerAccountReference
    ) -> [LedgerPosting] {
        [
            LedgerPosting(account: source, asset: asset, quantity: -quantity),
            LedgerPosting(account: destination, asset: asset, quantity: quantity)
        ]
    }

    private static func validateTrade(
        asset: LedgerAsset,
        quantity: Double,
        unitPrice: Double,
        settlementAsset: LedgerAsset,
        fee: Double
    ) throws {
        guard asset.kind == .equity || asset.kind == .etf || asset.kind == .cryptocurrency else {
            throw LedgerError.invalidTradeAsset
        }
        try positive(quantity)
        guard unitPrice.isFinite, unitPrice > 0 else { throw LedgerError.invalidPrice }
        guard fee.isFinite, fee >= 0 else { throw LedgerError.invalidFee }
        let validSettlementKind = settlementAsset.code == "USD"
            ? settlementAsset.kind == .fiat
            : settlementAsset.kind == .stablecoin
        guard allowedSettlementCodes.contains(settlementAsset.code), validSettlementKind else {
            throw LedgerError.unsupportedSettlementAsset
        }
    }

    private static func validateSpotAsset(_ asset: LedgerAsset) throws {
        guard asset.kind == .fiat || asset.kind == .stablecoin else {
            throw LedgerError.invalidSpotAsset
        }
    }

    private static func positive(_ quantity: Double) throws {
        guard quantity.isFinite, quantity > 0 else { throw LedgerError.invalidQuantity }
    }

    private static func normalizedNote(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return String(value.prefix(Holding.noteCharacterLimit))
    }
}

enum LedgerError: LocalizedError, Equatable {
    case unsupportedSchemaVersion
    case emptyEntry
    case invalidQuantity
    case unbalancedEntry
    case invalidAccount
    case invalidSpotAsset
    case invalidTradeAsset
    case invalidPrice
    case invalidFee
    case unsupportedSettlementAsset
    case insufficientBalance(account: LedgerAccountReference, asset: LedgerAsset)
    case duplicateEntryID
    case invalidReversal

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion: "This ledger version is not supported."
        case .emptyEntry: "A transaction must contain postings."
        case .invalidQuantity: "Enter an amount greater than 0."
        case .unbalancedEntry: "The transaction is not balanced."
        case .invalidAccount: "This account cannot be used for the transaction."
        case .invalidSpotAsset: "Fiat / Spot supports currencies and stablecoins only."
        case .invalidTradeAsset: "Only stocks, ETFs, and crypto can be traded."
        case .invalidPrice: "Enter a valid execution price."
        case .invalidFee: "Enter a valid fee smaller than the proceeds."
        case .unsupportedSettlementAsset: "Trades support USD, USDT, and USDC settlement only."
        case .insufficientBalance: "The selected account has insufficient balance."
        case .duplicateEntryID: "This transaction has already been recorded."
        case .invalidReversal: "This transaction cannot be reversed."
        }
    }
}
