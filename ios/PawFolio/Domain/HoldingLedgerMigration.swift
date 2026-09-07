import Foundation

struct HoldingLedgerMigrationResult: Equatable, Sendable {
    let entries: [LedgerEntry]
    let earnProducts: [EarnProduct]
    let skippedHoldingIDs: [String]
}

enum HoldingLedgerMigration {
    static let migrationVersion = 1

    /// 旧持仓只迁为一个可核对的期初快照，不倒推并伪造过去的资金流水。
    static func migrate(_ holdings: [Holding], openingAt: Date) -> HoldingLedgerMigrationResult {
        var entries: [LedgerEntry] = []
        var products: [EarnProduct] = []
        var skipped: [String] = []

        for holding in holdings where !holding.isDeleted && !holding.isClosed {
            let asset = ledgerAsset(for: holding)
            let quantity = openingQuantity(for: holding)
            guard quantity.isFinite, quantity > LedgerEntry.balanceTolerance else { continue }

            do {
                let destination: LedgerAccountReference
                if holding.isInterestBearing, (holding.annualRate ?? 0) > 0 {
                    let product = try EarnProduct(
                        id: "legacy-earn-\(holding.id)",
                        name: holding.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? asset.code : holding.name,
                        asset: asset,
                        annualRatePercent: max(0, holding.annualRate ?? 0),
                        interestMode: holding.interestMode ?? .simple,
                        term: .flexible,
                        payoutFrequency: .daily,
                        startsAt: openingAt,
                        note: "Migrated V2 position"
                    )
                    products.append(product)
                    destination = .earn(productID: product.id)
                } else if holding.holdingKind == .market || holding.holdingKind == .hybrid || holding.holdingKind == .dividend {
                    destination = .trading
                } else {
                    destination = .fiat("exchange")
                }

                entries.append(try LedgerEntry.openingBalance(
                    asset: asset,
                    quantity: quantity,
                    account: destination,
                    occurredAt: openingAt,
                    legacyHoldingID: holding.id,
                    unitCost: destination == .trading || destination.kind == .earn
                        ? holding.costPerShare : nil,
                    id: "legacy-opening-\(holding.id)"
                ))
            } catch {
                skipped.append(holding.id)
            }
        }

        return HoldingLedgerMigrationResult(entries: entries, earnProducts: products, skippedHoldingIDs: skipped)
    }

    private static func openingQuantity(for holding: Holding) -> Double {
        if holding.holdingKind == .interest {
            return max(0, holding.principal ?? 0)
        }
        return max(0, holding.quantity ?? holding.principal ?? 0)
    }

    private static func ledgerAsset(for holding: Holding) -> LedgerAsset {
        let kind: LedgerAsset.Kind
        switch holding.assetType {
        case .equity: kind = .equity
        case .etf: kind = .etf
        case .cryptocurrency: kind = .cryptocurrency
        case .stable: kind = .stablecoin
        case nil:
            let code = holding.symbol.uppercased()
            if ["USDT", "USDC", "DAI", "FDUSD"].contains(code) {
                kind = .stablecoin
            } else if holding.holdingKind == .interest {
                kind = .fiat
            } else {
                kind = .equity
            }
        }
        return LedgerAsset(code: holding.symbol, kind: kind)
    }
}
