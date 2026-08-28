import Foundation

struct HoldingMergeResult: Equatable, Sendable {
    let holdings: [Holding]
    let localChangedIDs: Set<String>
    let remoteUpserts: [Holding]

    var requiresLocalSave: Bool {
        !localChangedIDs.isEmpty
    }
}

enum HoldingMerge {
    static func reconcile(local: [Holding], remote: [Holding]) -> HoldingMergeResult {
        let localRecords = coalesced(local)
        let remoteRecords = coalesced(remote)
        let orderedIDs = stableIDs(local: local, remote: remote)

        var merged: [Holding] = []
        var localChangedIDs = Set<String>()
        var remoteUpserts: [Holding] = []

        for id in orderedIDs {
            let winner: Holding
            switch (localRecords[id], remoteRecords[id]) {
            case let (local?, remote?):
                winner = preferred(local: local, remote: remote)
            case let (local?, nil):
                winner = local
            case let (nil, remote?):
                winner = remote
            case (nil, nil):
                continue
            }

            let normalizedWinner = upgradedForNativeSync(winner)
            merged.append(normalizedWinner)

            if localRecords[id] != normalizedWinner {
                localChangedIDs.insert(id)
            }
            if remoteRecords[id] != normalizedWinner {
                remoteUpserts.append(normalizedWinner)
            }
        }

        return HoldingMergeResult(
            holdings: merged,
            localChangedIDs: localChangedIDs,
            remoteUpserts: remoteUpserts
        )
    }

    static func conflictTimestamp(for holding: Holding) -> TimeInterval {
        let contentTimestamp = validTimestamp(holding.updatedAt)
            ?? validTimestamp(holding.createdAt)
            ?? 0
        return max(contentTimestamp, validTimestamp(holding.deletedAt) ?? 0)
    }

    private static func preferred(local: Holding, remote: Holding) -> Holding {
        let localTimestamp = conflictTimestamp(for: local)
        let remoteTimestamp = conflictTimestamp(for: remote)

        if localTimestamp > remoteTimestamp { return local }
        if remoteTimestamp > localTimestamp { return remote }

        // A simultaneous delete must never be replaced by an active copy from
        // another device. For other exact ties, keep Web parity by preferring local.
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? local : remote
        }
        return local
    }

    private static func coalesced(_ holdings: [Holding]) -> [String: Holding] {
        var records: [String: Holding] = [:]
        for holding in holdings where !holding.id.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let existing = records[holding.id] else {
                records[holding.id] = holding
                continue
            }

            let existingTimestamp = conflictTimestamp(for: existing)
            let candidateTimestamp = conflictTimestamp(for: holding)
            if candidateTimestamp > existingTimestamp
                || (candidateTimestamp == existingTimestamp && holding.isDeleted) {
                records[holding.id] = holding
            }
        }
        return records
    }

    private static func stableIDs(local: [Holding], remote: [Holding]) -> [String] {
        var seen = Set<String>()
        return (local + remote).compactMap { holding in
            guard !holding.id.trimmingCharacters(in: .whitespaces).isEmpty,
                  seen.insert(holding.id).inserted else {
                return nil
            }
            return holding.id
        }
    }

    private static func upgradedForNativeSync(_ holding: Holding) -> Holding {
        guard holding.schemaVersion < Holding.currentSchemaVersion else { return holding }
        var upgraded = holding
        upgraded.schemaVersion = Holding.currentSchemaVersion
        return upgraded
    }

    private static func validTimestamp(_ value: TimeInterval?) -> TimeInterval? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}
