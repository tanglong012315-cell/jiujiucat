const test = require('node:test');
const assert = require('node:assert/strict');
const {
  HOLDING_SCHEMA_VERSION,
  holdingConflictStamp,
  isHoldingDeleted,
  mergeHoldings
} = require('../public/holding-sync.js');

function holding(id, updatedAt, extra = {}) {
  return { id, symbol: 'AAPL', createdAt: 100, updatedAt, ...extra };
}

test('newer payload wins and missing records are retained', () => {
  const local = [holding('shared', 300, { quantity: 3 }), holding('local', 250)];
  const remote = [holding('shared', 200, { quantity: 1 }), holding('remote', 275)];

  const merged = mergeHoldings(local, remote);

  assert.deepEqual(merged.map(item => item.id), ['shared', 'local', 'remote']);
  assert.equal(merged.find(item => item.id === 'shared').quantity, 3);
  assert.ok(merged.every(item => item.schemaVersion === HOLDING_SCHEMA_VERSION));
});

test('deletedAt participates in conflict resolution when updatedAt is missing', () => {
  const tombstone = holding('shared', null, { deletedAt: 400 });
  const active = holding('shared', 300);

  assert.equal(holdingConflictStamp(tombstone), 400);
  assert.equal(isHoldingDeleted(mergeHoldings([active], [tombstone])[0]), true);
});

test('tombstone wins an exact timestamp tie regardless of side', () => {
  const active = holding('shared', 400);
  const tombstone = holding('shared', 400, { deletedAt: 400 });

  assert.equal(isHoldingDeleted(mergeHoldings([active], [tombstone])[0]), true);
  assert.equal(isHoldingDeleted(mergeHoldings([tombstone], [active])[0]), true);
});

test('other exact ties prefer local and zero updatedAt falls back to createdAt', () => {
  const local = holding('shared', 0, { createdAt: 500, quantity: 5 });
  const remote = holding('shared', 500, { quantity: 1 });

  const [winner] = mergeHoldings([local], [remote]);

  assert.equal(winner.quantity, 5);
  assert.equal(holdingConflictStamp(local), 500);
});

test('future schema versions are preserved', () => {
  const [winner] = mergeHoldings([holding('future', 200, { schemaVersion: 7 })], []);
  assert.equal(winner.schemaVersion, 7);
});
