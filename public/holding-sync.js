(function exposeHoldingSync(root) {
  'use strict';

  const HOLDING_SCHEMA_VERSION = 2;

  function validTimestamp(value) {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? timestamp : 0;
  }

  function isHoldingDeleted(holding) {
    return holding?.deletedAt !== null && holding?.deletedAt !== undefined;
  }

  function holdingConflictStamp(holding) {
    const contentStamp = validTimestamp(holding?.updatedAt) || validTimestamp(holding?.createdAt);
    return Math.max(contentStamp, validTimestamp(holding?.deletedAt));
  }

  function upgradeHoldingSchema(holding) {
    const existingVersion = Number(holding?.schemaVersion);
    return {
      ...holding,
      schemaVersion: Number.isInteger(existingVersion) && existingVersion > HOLDING_SCHEMA_VERSION
        ? existingVersion
        : HOLDING_SCHEMA_VERSION
    };
  }

  function coalesced(holdings) {
    const records = new Map();
    for (const holding of Array.isArray(holdings) ? holdings : []) {
      const id = typeof holding?.id === 'string' ? holding.id.trim() : '';
      if (!id) continue;
      const existing = records.get(id);
      if (!existing) {
        records.set(id, holding);
        continue;
      }
      const existingStamp = holdingConflictStamp(existing);
      const candidateStamp = holdingConflictStamp(holding);
      if (candidateStamp > existingStamp
        || (candidateStamp === existingStamp && isHoldingDeleted(holding))) {
        records.set(id, holding);
      }
    }
    return records;
  }

  function mergeHoldings(local, remote) {
    const localRecords = coalesced(local);
    const remoteRecords = coalesced(remote);
    const orderedIDs = [];
    const seen = new Set();
    for (const holding of [...(local || []), ...(remote || [])]) {
      const id = typeof holding?.id === 'string' ? holding.id.trim() : '';
      if (id && !seen.has(id)) {
        seen.add(id);
        orderedIDs.push(id);
      }
    }

    return orderedIDs.map(id => {
      const localHolding = localRecords.get(id);
      const remoteHolding = remoteRecords.get(id);
      if (!localHolding) return upgradeHoldingSchema(remoteHolding);
      if (!remoteHolding) return upgradeHoldingSchema(localHolding);

      const localStamp = holdingConflictStamp(localHolding);
      const remoteStamp = holdingConflictStamp(remoteHolding);
      if (localStamp > remoteStamp) return upgradeHoldingSchema(localHolding);
      if (remoteStamp > localStamp) return upgradeHoldingSchema(remoteHolding);
      if (isHoldingDeleted(localHolding) !== isHoldingDeleted(remoteHolding)) {
        return upgradeHoldingSchema(isHoldingDeleted(localHolding) ? localHolding : remoteHolding);
      }
      return upgradeHoldingSchema(localHolding);
    });
  }

  const api = Object.freeze({
    HOLDING_SCHEMA_VERSION,
    holdingConflictStamp,
    isHoldingDeleted,
    mergeHoldings,
    upgradeHoldingSchema
  });

  root.PawFolioHoldingSync = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : window);
