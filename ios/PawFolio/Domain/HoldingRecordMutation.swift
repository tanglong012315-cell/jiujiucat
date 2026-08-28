import Foundation

struct DividendRecordRequest: Equatable, Sendable {
    let holdingID: String
    let recordID: String?
    let perShare: Double
    let frequency: DividendFrequency
    let exDate: String
    let payDate: String
    let occurredAt: TimeInterval
}

enum HoldingRecordError: LocalizedError, Equatable {
    case holdingNotFound
    case unavailableHolding
    case invalidTimestamp
    case invalidInterestDate
    case interestRecordNotFound
    case interestAlreadySkipped
    case skippedInterestNotFound
    case dividendRecordNotFound
    case invalidDividendAmount
    case invalidDividendDate
    case invalidDividendPayDate
    case invalidDividendQuantity

    var errorDescription: String? {
        switch self {
        case .holdingNotFound:
            "找不到对应的持仓。"
        case .unavailableHolding:
            "该持仓不支持这项记录操作。"
        case .invalidTimestamp:
            "记录时间无效。"
        case .invalidInterestDate:
            "利息结算日期无效。"
        case .interestRecordNotFound:
            "只能跳过已经结算的利息记录。"
        case .interestAlreadySkipped:
            "该结算日已经标记为未发放。"
        case .skippedInterestNotFound:
            "找不到要恢复的结算日。"
        case .dividendRecordNotFound:
            "找不到对应的分红记录。"
        case .invalidDividendAmount:
            "每股或每份分红必须大于 0。"
        case .invalidDividendDate:
            "请选择有效的除息日。"
        case .invalidDividendPayDate:
            "派息日不能早于除息日。"
        case .invalidDividendQuantity:
            "当前持仓数量无效，无法创建分红记录。"
        }
    }
}

enum HoldingRecordMutation {
    static func skippingInterestSettlement(
        holdingID: String,
        date: String,
        occurredAt: TimeInterval,
        in holdings: [Holding]
    ) throws -> [Holding] {
        guard occurredAt.isFinite, occurredAt >= 0 else {
            throw HoldingRecordError.invalidTimestamp
        }
        guard isValidDate(date) else { throw HoldingRecordError.invalidInterestDate }
        var candidate = holdings
        let index = try editableHoldingIndex(holdingID, in: candidate)
        guard candidate[index].isInterestBearing else {
            throw HoldingRecordError.unavailableHolding
        }
        guard !candidate[index].interestSkips.contains(date) else {
            throw HoldingRecordError.interestAlreadySkipped
        }
        guard HoldingValuation.interestRecordEntries(
            for: candidate[index],
            at: occurredAt
        ).contains(where: { $0.date == date }) else {
            throw HoldingRecordError.interestRecordNotFound
        }

        candidate[index].interestSkips.append(date)
        candidate[index].interestSkips = Array(Set(candidate[index].interestSkips)).sorted()
        markUpdated(&candidate[index], at: occurredAt)
        return candidate
    }

    static func restoringInterestSettlement(
        holdingID: String,
        date: String,
        occurredAt: TimeInterval,
        in holdings: [Holding]
    ) throws -> [Holding] {
        guard occurredAt.isFinite, occurredAt >= 0 else {
            throw HoldingRecordError.invalidTimestamp
        }
        var candidate = holdings
        let index = try editableHoldingIndex(holdingID, in: candidate)
        guard candidate[index].isInterestBearing else {
            throw HoldingRecordError.unavailableHolding
        }
        guard candidate[index].interestSkips.contains(date) else {
            throw HoldingRecordError.skippedInterestNotFound
        }

        candidate[index].interestSkips.removeAll { $0 == date }
        markUpdated(&candidate[index], at: occurredAt)
        return candidate
    }

    static func upsertingDividendRecord(
        _ request: DividendRecordRequest,
        in holdings: [Holding]
    ) throws -> [Holding] {
        guard request.occurredAt.isFinite, request.occurredAt >= 0 else {
            throw HoldingRecordError.invalidTimestamp
        }
        guard request.perShare.isFinite, request.perShare > 0 else {
            throw HoldingRecordError.invalidDividendAmount
        }
        guard isValidDate(request.exDate) else {
            throw HoldingRecordError.invalidDividendDate
        }
        guard request.payDate.isEmpty || isValidDate(request.payDate) else {
            throw HoldingRecordError.invalidDividendPayDate
        }
        guard request.payDate.isEmpty || request.payDate >= request.exDate else {
            throw HoldingRecordError.invalidDividendPayDate
        }

        var candidate = holdings
        let index = try editableHoldingIndex(request.holdingID, in: candidate)
        guard candidate[index].holdingKind == .dividend,
              let assetType = candidate[index].assetType,
              [.equity, .etf, .cryptocurrency].contains(assetType) else {
            throw HoldingRecordError.unavailableHolding
        }

        let currentQuantity = candidate[index].quantity ?? 0
        var recordID = request.recordID
        if let requestedID = request.recordID {
            guard let recordIndex = candidate[index].dividendRecords.firstIndex(where: {
                $0.id == requestedID
            }) else {
                throw HoldingRecordError.dividendRecordNotFound
            }
            let recordedQuantity = candidate[index].dividendRecords[recordIndex].quantity
            let frozenQuantity = recordedQuantity > 0 ? recordedQuantity : currentQuantity
            guard frozenQuantity.isFinite, frozenQuantity > 0 else {
                throw HoldingRecordError.invalidDividendQuantity
            }
            candidate[index].dividendRecords[recordIndex].perShare = request.perShare
            candidate[index].dividendRecords[recordIndex].quantity = frozenQuantity
            candidate[index].dividendRecords[recordIndex].amount = frozenQuantity * request.perShare
            candidate[index].dividendRecords[recordIndex].frequency = request.frequency
            candidate[index].dividendRecords[recordIndex].exDate = request.exDate
            candidate[index].dividendRecords[recordIndex].payDate = request.payDate
        } else {
            guard currentQuantity.isFinite, currentQuantity > 0 else {
                throw HoldingRecordError.invalidDividendQuantity
            }
            let createdID = identifier(timestamp: request.occurredAt)
            recordID = createdID
            candidate[index].dividendRecords.append(
                DividendRecord(
                    id: createdID,
                    perShare: request.perShare,
                    quantity: currentQuantity,
                    amount: currentQuantity * request.perShare,
                    frequency: request.frequency,
                    exDate: request.exDate,
                    payDate: request.payDate,
                    createdAt: request.occurredAt
                )
            )
        }

        if request.recordID == nil || candidate[index].dividendRecordId == request.recordID {
            candidate[index].dividendRecordId = recordID
            candidate[index].dividendPerShare = request.perShare
            candidate[index].dividendFrequency = request.frequency
            candidate[index].dividendExDate = request.exDate
            candidate[index].dividendPayDate = request.payDate.isEmpty ? nil : request.payDate
        }
        markUpdated(&candidate[index], at: request.occurredAt)
        return candidate
    }

    static func deletingDividendRecord(
        holdingID: String,
        recordID: String,
        occurredAt: TimeInterval,
        in holdings: [Holding]
    ) throws -> [Holding] {
        guard occurredAt.isFinite, occurredAt >= 0 else {
            throw HoldingRecordError.invalidTimestamp
        }
        var candidate = holdings
        let index = try editableHoldingIndex(holdingID, in: candidate)
        guard candidate[index].holdingKind == .dividend else {
            throw HoldingRecordError.unavailableHolding
        }
        guard candidate[index].dividendRecords.contains(where: { $0.id == recordID }) else {
            throw HoldingRecordError.dividendRecordNotFound
        }

        candidate[index].dividendRecords.removeAll { $0.id == recordID }
        if candidate[index].dividendRecordId == recordID {
            candidate[index].dividendRecordId = nil
            candidate[index].dividendPerShare = nil
            candidate[index].dividendFrequency = nil
            candidate[index].dividendExDate = nil
            candidate[index].dividendPayDate = nil
        }
        markUpdated(&candidate[index], at: occurredAt)
        return candidate
    }

    private static func editableHoldingIndex(
        _ holdingID: String,
        in holdings: [Holding]
    ) throws -> Int {
        guard let index = holdings.firstIndex(where: { $0.id == holdingID }) else {
            throw HoldingRecordError.holdingNotFound
        }
        guard !holdings[index].isDeleted, !holdings[index].isClosed else {
            throw HoldingRecordError.unavailableHolding
        }
        return index
    }

    private static func markUpdated(_ holding: inout Holding, at timestamp: TimeInterval) {
        holding.schemaVersion = Holding.currentSchemaVersion
        holding.updatedAt = timestamp
    }

    private static func identifier(timestamp: TimeInterval) -> String {
        "d_\(Int(timestamp))_\(UUID().uuidString.prefix(5).lowercased())"
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
