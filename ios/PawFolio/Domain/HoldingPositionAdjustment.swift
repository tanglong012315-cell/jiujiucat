import Foundation

struct HoldingAdjustmentRequest: Equatable, Sendable {
    let holdingID: String
    let type: PositionAdjustmentKind
    let amount: Double
    let transactionPrice: Double?
    let effectiveDate: String?
    let occurredAt: TimeInterval

    init(
        holdingID: String,
        type: PositionAdjustmentKind,
        amount: Double,
        transactionPrice: Double? = nil,
        effectiveDate: String? = nil,
        occurredAt: TimeInterval
    ) {
        self.holdingID = holdingID
        self.type = type
        self.amount = amount
        self.transactionPrice = transactionPrice
        self.effectiveDate = effectiveDate
        self.occurredAt = occurredAt
    }
}

enum HoldingAdjustmentError: LocalizedError, Equatable {
    case holdingNotFound
    case holdingUnavailable
    case invalidTimestamp
    case invalidAmount
    case invalidTransactionPrice
    case invalidEffectiveDate
    case effectiveDateBeforeToday
    case insufficientQuantity
    case insufficientPrincipal

    var errorDescription: String? {
        switch self {
        case .holdingNotFound:
            "找不到要调整的持仓。"
        case .holdingUnavailable:
            "已删除或已清仓的持仓不能再调整。"
        case .invalidTimestamp:
            "持仓调整时间无效。"
        case .invalidAmount:
            "请输入大于 0 的调整数量或金额。"
        case .invalidTransactionPrice:
            "暂时无法取得美元实时价，请填写有效的成交价格。"
        case .invalidEffectiveDate:
            "请选择有效的本金调整生效日期。"
        case .effectiveDateBeforeToday:
            "生效日期不能早于今天，避免改写已结算利息。"
        case .insufficientQuantity:
            "减仓数量不能超过当前持有数量。"
        case .insufficientPrincipal:
            "减仓金额必须小于当前本金；全部赎回请删除持仓。"
        }
    }
}

enum HoldingPositionAdjustment {
    static let closedHistoryRetentionMilliseconds: TimeInterval = 400 * HoldingValuation.dayMilliseconds

    static func applying(
        _ request: HoldingAdjustmentRequest,
        to holdings: [Holding]
    ) throws -> [Holding] {
        guard request.amount.isFinite, request.amount > 0 else {
            throw HoldingAdjustmentError.invalidAmount
        }
        guard request.occurredAt.isFinite, request.occurredAt >= 0 else {
            throw HoldingAdjustmentError.invalidTimestamp
        }
        guard let sourceIndex = holdings.firstIndex(where: { $0.id == request.holdingID }) else {
            throw HoldingAdjustmentError.holdingNotFound
        }
        guard !holdings[sourceIndex].isDeleted, !holdings[sourceIndex].isClosed else {
            throw HoldingAdjustmentError.holdingUnavailable
        }

        var candidate = holdings
        if candidate[sourceIndex].holdingKind == .interest {
            try adjustInterestHolding(at: sourceIndex, request: request, in: &candidate)
        } else {
            try adjustMarketHolding(at: sourceIndex, request: request, in: &candidate)
        }
        return candidate
    }

    static func retainedClosedHistory(
        from holdings: [Holding],
        at timestampMilliseconds: TimeInterval
    ) -> [Holding] {
        holdings.filter { holding in
            guard !holding.isDeleted else { return true }
            guard let closedAt = holding.closedAt else { return true }
            return timestampMilliseconds - closedAt < closedHistoryRetentionMilliseconds
        }
    }

    private static func adjustInterestHolding(
        at index: Int,
        request: HoldingAdjustmentRequest,
        in holdings: inout [Holding]
    ) throws {
        let today = HoldingValuation.beijingDateString(timestampMilliseconds: request.occurredAt)
        let effectiveDate = request.effectiveDate ?? today
        guard isValidDate(effectiveDate) else {
            throw HoldingAdjustmentError.invalidEffectiveDate
        }
        guard effectiveDate >= today else {
            throw HoldingAdjustmentError.effectiveDateBeforeToday
        }

        let currentPrincipal = holdings[index].principal ?? 0
        guard currentPrincipal.isFinite, currentPrincipal > 0 else {
            throw HoldingAdjustmentError.invalidAmount
        }
        if request.type == .reduce, request.amount >= currentPrincipal {
            throw HoldingAdjustmentError.insufficientPrincipal
        }

        let delta = request.type == .add ? request.amount : -request.amount
        holdings[index].principal = currentPrincipal + delta
        holdings[index].principalAdjustments.append(
            PrincipalAdjustment(
                id: identifier(prefix: "p", timestamp: request.occurredAt),
                type: request.type,
                amount: request.amount,
                date: effectiveDate,
                createdAt: request.occurredAt
            )
        )
        markUpdated(&holdings[index], at: request.occurredAt)
    }

    private static func adjustMarketHolding(
        at index: Int,
        request: HoldingAdjustmentRequest,
        in holdings: inout [Holding]
    ) throws {
        guard let transactionPrice = request.transactionPrice,
              transactionPrice.isFinite,
              transactionPrice > 0 else {
            throw HoldingAdjustmentError.invalidTransactionPrice
        }

        let currentQuantity = holdings[index].quantity ?? 0
        guard currentQuantity.isFinite, currentQuantity > 0 else {
            throw HoldingAdjustmentError.invalidAmount
        }
        if request.type == .reduce, request.amount > currentQuantity + 1e-9 {
            throw HoldingAdjustmentError.insufficientQuantity
        }

        let currentCost = holdings[index].costPerShare.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? transactionPrice
        let previousInterestPrincipal = interestPrincipal(for: holdings[index])
        let soldAll = request.type == .reduce
            && abs(request.amount - currentQuantity) < 1e-9

        switch request.type {
        case .add:
            let nextQuantity = currentQuantity + request.amount
            holdings[index].costPerShare = (
                currentQuantity * currentCost + request.amount * transactionPrice
            ) / nextQuantity
            holdings[index].quantity = nextQuantity
        case .reduce:
            holdings[index].quantity = soldAll ? 0 : currentQuantity - request.amount
        }

        let today = HoldingValuation.beijingDateString(timestampMilliseconds: request.occurredAt)
        if holdings[index].holdingKind == .hybrid {
            let principalDelta = interestPrincipal(for: holdings[index]) - previousInterestPrincipal
            if abs(principalDelta) >= 1e-9 {
                holdings[index].principalAdjustments.append(
                    PrincipalAdjustment(
                        id: identifier(prefix: "p", timestamp: request.occurredAt),
                        type: principalDelta < 0 ? .reduce : .add,
                        amount: abs(principalDelta),
                        date: today,
                        createdAt: request.occurredAt
                    )
                )
            }
        }

        holdings[index].positionAdjustments.append(
            PositionAdjustment(
                id: identifier(prefix: "t", timestamp: request.occurredAt),
                type: request.type,
                quantity: request.amount,
                price: transactionPrice,
                createdAt: request.occurredAt
            )
        )

        if request.type == .reduce {
            creditSaleProceeds(
                request.amount * transactionPrice,
                at: request.occurredAt,
                date: today,
                in: &holdings
            )
            if soldAll {
                holdings[index].closedAt = request.occurredAt
            }
        }

        for recordIndex in holdings[index].dividendRecords.indices
        where holdings[index].dividendRecords[recordIndex].exDate > today {
            let quantity = holdings[index].quantity ?? 0
            holdings[index].dividendRecords[recordIndex].quantity = quantity
            holdings[index].dividendRecords[recordIndex].amount = quantity
                * holdings[index].dividendRecords[recordIndex].perShare
        }
        markUpdated(&holdings[index], at: request.occurredAt)
    }

    private static func creditSaleProceeds(
        _ amount: Double,
        at timestamp: TimeInterval,
        date: String,
        in holdings: inout [Holding]
    ) {
        guard amount.isFinite, amount > 0 else { return }

        if let index = holdings.firstIndex(where: {
            $0.holdingKind == .interest
                && !$0.isClosed
                && !$0.isDeleted
                && $0.symbol.uppercased() == "USDT"
        }) {
            holdings[index].principal = max(0, holdings[index].principal ?? 0) + amount
            holdings[index].principalAdjustments.append(
                PrincipalAdjustment(
                    id: identifier(prefix: "p", timestamp: timestamp),
                    type: .add,
                    amount: amount,
                    date: date,
                    at: timestamp,
                    createdAt: timestamp
                )
            )
            markUpdated(&holdings[index], at: timestamp)
            return
        }

        holdings.append(
            Holding(
                id: identifier(prefix: "h", timestamp: timestamp),
                symbol: "USDT",
                quoteSymbol: "USDT",
                name: "USDT",
                assetType: nil,
                exchange: "",
                holdingKind: .interest,
                principal: amount,
                annualRate: 0,
                interestMode: .simple,
                interestStartDate: date,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        )
    }

    private static func markUpdated(_ holding: inout Holding, at timestamp: TimeInterval) {
        holding.schemaVersion = Holding.currentSchemaVersion
        holding.updatedAt = timestamp
    }

    private static func interestPrincipal(for holding: Holding) -> Double {
        max(0, holding.quantity ?? 0) * max(0, holding.costPerShare ?? 0)
    }

    private static func identifier(prefix: String, timestamp: TimeInterval) -> String {
        "\(prefix)_\(Int(timestamp))_\(UUID().uuidString.prefix(5).lowercased())"
    }

    private static func isValidDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
}
