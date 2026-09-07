import Foundation

struct LedgerBalanceKey: Hashable, Sendable {
    let account: LedgerAccountReference
    let asset: LedgerAsset
}

struct TradingPosition: Equatable, Sendable {
    let asset: LedgerAsset
    var quantity: Double
    var costBasis: Double

    var averageCost: Double { quantity > 0 ? costBasis / quantity : 0 }
}

struct LedgerProjection: Equatable, Sendable {
    private(set) var balances: [LedgerBalanceKey: Double] = [:]
    private(set) var tradingPositions: [LedgerAsset: TradingPosition] = [:]
    /// Crypto Earn keeps the transferred market cost separate from interest yield.
    private(set) var earnPositions: [String: TradingPosition] = [:]
    private(set) var appliedEntryIDs: Set<String> = []

    init() {}

    init(entries: [LedgerEntry]) throws {
        let ordered = entries.sorted(by: Self.entryOrder)
        let grouped = Dictionary(grouping: ordered, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw LedgerError.duplicateEntryID }
        let indexed = grouped.mapValues { $0[0] }

        var reversedEntryIDs: Set<String> = []
        for entry in ordered where entry.kind == .reversal {
            guard let targetID = entry.reversesEntryID,
                  let target = indexed[targetID],
                  target.kind != .reversal,
                  target.occurredAt <= entry.occurredAt,
                  reversedEntryIDs.insert(targetID).inserted,
                  Self.isExactInverse(entry, of: target) else {
                throw LedgerError.invalidReversal
            }
        }

        for entry in ordered where entry.kind != .reversal && !reversedEntryIDs.contains(entry.id) {
            try apply(entry)
        }
        appliedEntryIDs = Set(ordered.map(\.id))
    }

    func balance(in account: LedgerAccountReference, asset: LedgerAsset) -> Double {
        balances[LedgerBalanceKey(account: account, asset: asset), default: 0]
    }

    mutating func apply(_ entry: LedgerEntry) throws {
        try entry.validate()
        guard entry.kind != .reversal else { throw LedgerError.invalidReversal }
        guard appliedEntryIDs.insert(entry.id).inserted else { throw LedgerError.duplicateEntryID }

        var candidate = balances
        for posting in entry.postings where posting.account.isUserControlled {
            let key = LedgerBalanceKey(account: posting.account, asset: posting.asset)
            candidate[key, default: 0] += posting.quantity
            if candidate[key, default: 0] < -LedgerEntry.balanceTolerance {
                appliedEntryIDs.remove(entry.id)
                throw LedgerError.insufficientBalance(account: posting.account, asset: posting.asset)
            }
            if abs(candidate[key, default: 0]) <= LedgerEntry.balanceTolerance {
                candidate[key] = 0
            }
        }

        balances = candidate
        applyOpeningCost(entry)
        applyTradeCost(entry)
        applyEarnCostTransfer(entry)
    }

    private static func isExactInverse(_ reversal: LedgerEntry, of target: LedgerEntry) -> Bool {
        guard reversal.postings.count == target.postings.count else { return false }
        var remaining = target.postings
        for posting in reversal.postings {
            guard let index = remaining.firstIndex(where: {
                $0.account == posting.account
                    && $0.asset == posting.asset
                    && abs($0.quantity + posting.quantity) <= LedgerEntry.balanceTolerance
            }) else { return false }
            remaining.remove(at: index)
        }
        return remaining.isEmpty
    }

    private mutating func applyOpeningCost(_ entry: LedgerEntry) {
        guard entry.kind == .openingBalance,
              let unitCost = entry.openingUnitCost,
              let posting = entry.postings.first(where: { $0.account.isUserControlled && $0.quantity > 0 }) else {
            return
        }
        if posting.account.kind == .earn {
            var position = earnPositions[posting.account.identifier]
                ?? TradingPosition(asset: posting.asset, quantity: 0, costBasis: 0)
            position.quantity += posting.quantity
            position.costBasis += posting.quantity * unitCost
            earnPositions[posting.account.identifier] = position
            return
        }
        guard posting.account == .trading else { return }
        var position = tradingPositions[posting.asset]
            ?? TradingPosition(asset: posting.asset, quantity: 0, costBasis: 0)
        position.quantity += posting.quantity
        position.costBasis += posting.quantity * unitCost
        tradingPositions[posting.asset] = position
    }

    private mutating func applyTradeCost(_ entry: LedgerEntry) {
        guard let trade = entry.trade,
              let assetPosting = entry.postings.first(where: {
                  $0.account == .trading && $0.asset != trade.settlementAsset
              }) else { return }

        var position = tradingPositions[assetPosting.asset]
            ?? TradingPosition(asset: assetPosting.asset, quantity: 0, costBasis: 0)
        switch entry.kind {
        case .buy:
            position.quantity += assetPosting.quantity
            position.costBasis += assetPosting.quantity * trade.unitPrice + trade.fee
        case .sell:
            let sold = abs(assetPosting.quantity)
            let removedCost = min(position.costBasis, sold * position.averageCost)
            position.quantity = max(0, position.quantity - sold)
            position.costBasis = position.quantity <= LedgerEntry.balanceTolerance
                ? 0
                : max(0, position.costBasis - removedCost)
        default:
            break
        }
        tradingPositions[assetPosting.asset] = position
    }

    private mutating func applyEarnCostTransfer(_ entry: LedgerEntry) {
        guard let productID = entry.earnProductID,
              let tradingPosting = entry.postings.first(where: { $0.account == .trading }),
              tradingPosting.asset.kind == .cryptocurrency else { return }

        var trading = tradingPositions[tradingPosting.asset]
            ?? TradingPosition(asset: tradingPosting.asset, quantity: 0, costBasis: 0)
        var earn = earnPositions[productID]
            ?? TradingPosition(asset: tradingPosting.asset, quantity: 0, costBasis: 0)

        switch entry.kind {
        case .earnSubscribe:
            let transferred = abs(tradingPosting.quantity)
            let transferredCost = min(trading.costBasis, transferred * trading.averageCost)
            trading.quantity = max(0, trading.quantity - transferred)
            trading.costBasis = trading.quantity <= LedgerEntry.balanceTolerance
                ? 0 : max(0, trading.costBasis - transferredCost)
            earn.quantity += transferred
            earn.costBasis += transferredCost
        case .earnRedeem:
            let transferred = abs(tradingPosting.quantity)
            let transferredCost = min(earn.costBasis, transferred * earn.averageCost)
            earn.quantity = max(0, earn.quantity - transferred)
            earn.costBasis = earn.quantity <= LedgerEntry.balanceTolerance
                ? 0 : max(0, earn.costBasis - transferredCost)
            trading.quantity += transferred
            trading.costBasis += transferredCost
        default:
            return
        }

        tradingPositions[tradingPosting.asset] = trading
        earnPositions[productID] = earn
    }

    private static func entryOrder(_ lhs: LedgerEntry, _ rhs: LedgerEntry) -> Bool {
        lhs.occurredAt == rhs.occurredAt ? lhs.id < rhs.id : lhs.occurredAt < rhs.occurredAt
    }
}
