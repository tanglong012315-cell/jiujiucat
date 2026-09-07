import Foundation

enum EarnProductTerm: String, Codable, CaseIterable, Sendable {
    case flexible
    case fixed
    case structured
}

enum EarnPayoutFrequency: String, Codable, CaseIterable, Sendable {
    /// 整点派息。设计 `155:16083` 的第一项，也是新建产品的默认值。
    case hourly
    case daily
    case weekly
    /// 设计 `155:16083` 的选项里没有月付，留着只为让旧账本里已存在的产品
    /// 照常解码和展示；新建时选不到它。
    case monthly
    case atMaturity
}

struct EarnRateChange: Codable, Equatable, Sendable {
    let annualRatePercent: Double
    let effectiveAt: Date
}

struct EarnProduct: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var asset: LedgerAsset
    var annualRatePercent: Double
    var interestMode: InterestMode
    var term: EarnProductTerm
    var payoutFrequency: EarnPayoutFrequency
    var startsAt: Date
    var maturesAt: Date?
    var note: String?
    /// Kept optional so snapshots written by the first schema-v3 build remain decodable.
    var initialAnnualRatePercent: Double?
    var rateHistory: [EarnRateChange]?
    /// V2.1 only records and displays provider-defined structured terms; it does not settle them.
    /// 旧字段：第一版把结构化条款塞在一个自由文本里。设计 `155:15932` 把它拆成了
    /// Strike / Knock-Out 两个独立必填价格，新建的产品走下面两个字段，这个只保留读。
    var structuredParameters: String?
    /// 固定票息的行权价（设计 `155:15940`）。
    var strikePrice: Double?
    /// 固定票息的敲出价（设计 `155:16010`）。
    var knockOutPrice: Double?
    /// 下架时间。三种 Earn 产品都能下架（用户 2026-09-05 最新确认）：下架后本金全额退回来源账户，
    /// 产品不再出现在 Product / Holding 列表里，但记录保留——历史流水还要靠它显示当时的
    /// 名字和 APY。可选是为了让第一版 schema-v3 写下的快照仍然能解码。
    var delistedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        asset: LedgerAsset,
        annualRatePercent: Double,
        interestMode: InterestMode,
        term: EarnProductTerm,
        payoutFrequency: EarnPayoutFrequency,
        startsAt: Date,
        maturesAt: Date? = nil,
        note: String? = nil,
        initialAnnualRatePercent: Double? = nil,
        rateHistory: [EarnRateChange]? = nil,
        structuredParameters: String? = nil,
        strikePrice: Double? = nil,
        knockOutPrice: Double? = nil,
        delistedAt: Date? = nil
    ) throws {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.asset = asset
        self.annualRatePercent = annualRatePercent
        self.interestMode = interestMode
        self.term = term
        self.payoutFrequency = payoutFrequency
        self.startsAt = startsAt
        self.maturesAt = maturesAt
        self.note = note
        self.initialAnnualRatePercent = initialAnnualRatePercent
        self.rateHistory = rateHistory
        self.structuredParameters = structuredParameters?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.strikePrice = strikePrice
        self.knockOutPrice = knockOutPrice
        self.delistedAt = delistedAt
        try validate()
    }

    var isDelisted: Bool { delistedAt != nil }

    /// 活期、定期和结构化产品使用同一套下架流程。
    var canDelist: Bool { !isDelisted }

    /// 只支持全额赎回，不能填部分金额。定期是用户 2026-09-05 定的；
    /// 结构化见设计 `155:13496` 的注释「结构化理财只能全部赎回全部金额，
    /// 不能赎回一部分或加仓」。活期才可以部分赎回。
    var redeemsFullAmountOnly: Bool { term == .fixed || term == .structured }

    /// 能不能加仓。设计 `158:17375` / `158:16698` 的注释：
    /// 「定期产品不能加仓，只能单独申购」「结构产品不能加仓，只能单独申购」——
    /// 只有活期能在已有持仓上继续申购，所以只有活期的明细页有 Subscribe。
    var allowsAdditionalSubscription: Bool { term == .flexible }

    /// 提前赎回还能不能拿到利息。定期是「赎回没有收益」（设计 `158:17375` 注释）；
    /// 活期和结构化的已产生利息不受赎回影响。
    var forfeitsInterestOnEarlyRedemption: Bool { term == .fixed }

    var fundingAccount: LedgerAccountReference {
        get throws {
            guard asset.canEnterEarn else { throw EarnProductError.unsupportedAsset }
            return asset.kind == .cryptocurrency ? .trading : .fiat("exchange")
        }
    }

    func validate() throws {
        guard !name.isEmpty else { throw EarnProductError.missingName }
        guard asset.canEnterEarn else { throw EarnProductError.unsupportedAsset }
        guard annualRatePercent.isFinite, annualRatePercent >= 0, annualRatePercent <= 1_000 else {
            throw EarnProductError.invalidAnnualRate
        }
        if term == .fixed, interestMode != .simple {
            throw EarnProductError.fixedMustUseSimpleInterest
        }
        if term == .structured, interestMode != .simple {
            throw EarnProductError.structuredMustUseSimpleInterest
        }
        // 固定票息的条款：新记录填 Strike + Knock-Out 两个价格（设计 `155:15940` /
        // `155:16010`），第一版写下的记录只有一段自由文本。两种都算数，
        // 否则旧账本在 `load` 时会整个读不出来。
        if term == .structured {
            let hasPrices = strikePrice != nil && knockOutPrice != nil
            let hasLegacyText = structuredParameters?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasPrices || hasLegacyText else {
                throw EarnProductError.missingStructuredParameters
            }
        }
        for price in [strikePrice, knockOutPrice].compactMap({ $0 }) {
            guard price.isFinite, price > 0 else { throw EarnProductError.invalidStructuredPrice }
        }
        for change in rateHistory ?? [] {
            guard change.annualRatePercent.isFinite,
                  (0...1_000).contains(change.annualRatePercent) else {
                throw EarnProductError.invalidAnnualRate
            }
        }
        if term == .fixed || payoutFrequency == .atMaturity {
            guard let maturesAt, maturesAt > startsAt else { throw EarnProductError.invalidMaturity }
        }
    }

    func annualRate(at date: Date) -> Double {
        let base = initialAnnualRatePercent ?? annualRatePercent
        return (rateHistory ?? [])
            .filter { $0.effectiveAt <= date }
            .sorted { $0.effectiveAt < $1.effectiveAt }
            .last?.annualRatePercent ?? base
    }

    mutating func scheduleAnnualRate(_ rate: Double, effectiveAt: Date) throws {
        guard rate.isFinite, (0...1_000).contains(rate) else {
            throw EarnProductError.invalidAnnualRate
        }
        if initialAnnualRatePercent == nil {
            initialAnnualRatePercent = annualRatePercent
        }
        var changes = rateHistory ?? []
        changes.removeAll { $0.effectiveAt == effectiveAt }
        changes.append(EarnRateChange(annualRatePercent: rate, effectiveAt: effectiveAt))
        changes.sort { $0.effectiveAt < $1.effectiveAt }
        rateHistory = changes
        annualRatePercent = rate
        try validate()
    }

    /// 派息钟点钉在当地时间下午四点（用户 2026-09-05）。设计 `155:16083` 的选项
    /// 直接把它写进了文案——「16:00 , Daily」「16:00 Friday, Weekly」——明细页的
    /// `Next Time Payout` 也一律是 `16:00 Sep 4 2026`。
    ///
    /// 这条规则之前不存在：`nextPayout` 是从 `startsAt` 往后加周期，于是派息点继承
    /// 了「按下保存那一刻」的时分秒，每个产品的派息时间都不一样。
    static let payoutHour = 16
    /// 周付固定在周五（设计 `155:16083`）。Gregorian 里 1 是周日，所以周五是 6。
    static let weeklyPayoutWeekday = 6

    /// 日/周/月产品的申购在下一个 16:00 边界起息；Hourly 产品在下一个整点起息。
    /// 申购流水本身仍保留提交时间，账户投影因此会立即锁定资金；只有收益计算使用
    /// 这个 Effective Date。这里仅计算起息，不代表此刻已经可以派息。
    static func subscriptionEffectiveDate(
        for submittedAt: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let cutoff = calendar.date(
            bySettingHour: payoutHour,
            minute: 0,
            second: 0,
            of: submittedAt
        ) else {
            return submittedAt
        }
        guard submittedAt >= cutoff else { return cutoff }
        return calendar.date(byAdding: .day, value: 1, to: cutoff) ?? cutoff.addingTimeInterval(86_400)
    }

    func subscriptionEffectiveDate(
        for submittedAt: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard payoutFrequency == .hourly else {
            return Self.subscriptionEffectiveDate(for: submittedAt, calendar: calendar)
        }
        return calendar.nextDate(
            after: submittedAt,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? submittedAt.addingTimeInterval(3_600)
    }

    /// 一笔申购第一次允许派息的时间。起息只代表开始累计收益；必须从起息时刻完整经过
    /// 一个对应周期，才会产生第一笔可登记的派息。At Maturity 仍只在到期时派一次。
    func firstPayoutDate(
        forSubscriptionAt submittedAt: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if payoutFrequency == .atMaturity { return maturesAt }

        let effectiveAt = subscriptionEffectiveDate(for: submittedAt, calendar: calendar)
        let fullCycleEnd: Date?
        switch payoutFrequency {
        case .hourly:
            fullCycleEnd = calendar.date(byAdding: .hour, value: 1, to: effectiveAt)
        case .daily:
            fullCycleEnd = calendar.date(byAdding: .day, value: 1, to: effectiveAt)
        case .weekly:
            fullCycleEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: effectiveAt)
        case .monthly:
            fullCycleEnd = calendar.date(byAdding: .month, value: 1, to: effectiveAt)
        case .atMaturity:
            fullCycleEnd = maturesAt
        }
        guard let fullCycleEnd else { return nil }

        let candidate: Date?
        switch payoutFrequency {
        case .hourly, .daily:
            // Effective Date 本身已经落在该频率的整点，完整加一个周期后就是首派时刻。
            candidate = fullCycleEnd
        case .weekly:
            candidate = scheduledWeeklyPayout(onOrAfter: fullCycleEnd, calendar: calendar)
        case .monthly:
            candidate = nextMonthlyPayout(
                after: fullCycleEnd.addingTimeInterval(-1),
                calendar: calendar
            )
        case .atMaturity:
            candidate = maturesAt
        }
        guard let candidate else { return nil }
        if let maturesAt, candidate > maturesAt { return nil }
        return candidate
    }

    /// 返回 `date` 之后的下一次真实派息点；复利只在这个时间点入本金。
    func nextPayout(after date: Date, calendar: Calendar = .current) -> Date? {
        if payoutFrequency == .atMaturity {
            guard let maturesAt, maturesAt > date else { return nil }
            return maturesAt
        }
        // 产品创建时间也是首次申购流程的提交时间基准。第一笔派息必须晚于起息整整
        // 一个周期；不能把起息边界本身返回成派息时间。
        guard let firstPayout = firstPayoutDate(
            forSubscriptionAt: startsAt,
            calendar: calendar
        ) else { return nil }
        if date < firstPayout { return firstPayout }

        let candidate: Date?
        switch payoutFrequency {
        case .hourly:
            candidate = calendar.nextDate(
                after: date,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
        case .daily:
            candidate = calendar.nextDate(
                after: date,
                matching: DateComponents(hour: Self.payoutHour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
        case .weekly:
            candidate = calendar.nextDate(
                after: date,
                matching: DateComponents(
                    hour: Self.payoutHour,
                    minute: 0,
                    second: 0,
                    weekday: Self.weeklyPayoutWeekday
                ),
                matchingPolicy: .nextTime
            )
        case .monthly:
            candidate = nextMonthlyPayout(after: date, calendar: calendar)
        case .atMaturity:
            candidate = maturesAt
        }
        guard let candidate else { return nil }
        if let maturesAt, candidate > maturesAt { return nil }
        return candidate
    }

    private func scheduledWeeklyPayout(onOrAfter date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        if components.weekday == Self.weeklyPayoutWeekday,
           components.hour == Self.payoutHour,
           components.minute == 0,
           components.second == 0 {
            return date
        }
        return calendar.nextDate(
            after: date,
            matching: DateComponents(
                hour: Self.payoutHour,
                minute: 0,
                second: 0,
                weekday: Self.weeklyPayoutWeekday
            ),
            matchingPolicy: .nextTime
        )
    }

    /// 月付锚定起息日的「几号」再套上 16:00：1 月 31 日起息的产品走
    /// 2 月 28 → 3 月 31，不会被短二月带着一路往前漂。
    /// 这件事 `Calendar.nextDate(matching:)` 做不到（它会直接跳过没有 31 号的月份），
    /// 所以月付单独走加月份的循环。
    private func nextMonthlyPayout(after floor: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: startsAt)
        components.hour = Self.payoutHour
        components.minute = 0
        components.second = 0
        guard let anchor = calendar.date(from: components) else { return nil }
        var candidate = anchor
        var occurrence = 0
        while candidate <= floor {
            occurrence += 1
            guard let next = calendar.date(byAdding: .month, value: occurrence, to: anchor) else { return nil }
            candidate = next
        }
        return candidate
    }
}

enum EarnProductError: LocalizedError, Equatable {
    case missingName
    case unsupportedAsset
    case invalidAnnualRate
    case fixedMustUseSimpleInterest
    case structuredMustUseSimpleInterest
    case missingStructuredParameters
    case invalidStructuredPrice
    case invalidMaturity

    var errorDescription: String? {
        switch self {
        case .missingName: "Enter a product name."
        case .unsupportedAsset: "Earn supports fiat, stablecoins, and crypto only."
        case .invalidAnnualRate: "APY must be between 0% and 1,000%."
        case .fixedMustUseSimpleInterest: "Fixed products support simple interest only."
        case .structuredMustUseSimpleInterest: "Structured products support simple interest only."
        case .missingStructuredParameters: "Enter the strike and knock-out prices."
        case .invalidStructuredPrice: "Enter prices greater than 0."
        case .invalidMaturity: "Select a maturity date after the start date."
        }
    }
}
