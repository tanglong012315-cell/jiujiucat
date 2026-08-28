# PawFolio native/Web holding sync contract

This contract must be implemented by both clients before native cloud sync is enabled. The current Web app is the migration source, but its physical remote-delete behavior is not safe for offline multi-device sync.

## Row identity and ownership

- Each logical holding is one Supabase `holdings` row.
- The logical key is `(user_id, id)`. `id` is the payload holding ID and must be a non-empty stable string.
- Row-level security must continue to require `auth.uid() = user_id` for reads and writes.
- Before production sync, migrate the current global `id` primary key to a composite primary key or unique constraint on `(user_id, id)`, then use those columns as the upsert conflict target.

## Payload rules

- `payload` remains the complete holding JSON object so the existing Web shape stays compatible.
- Every native remote write includes `schemaVersion >= 2`.
- Timestamp numbers inside the payload are Unix epoch milliseconds, not seconds.
- `createdAt` is the legacy fallback timestamp. Every content mutation sets `updatedAt` only on the changed holding.
- Arrays such as `positionAdjustments`, `principalAdjustments`, `interestSkips`, and `dividendRecords` remain inside the holding payload.
- Missing optional legacy fields continue to decode with the native compatibility defaults. Unknown future fields must be ignored by older clients.
- The row-level `updated_at` may mirror the payload conflict timestamp for diagnostics, but clients use the payload timestamps as the conflict authority.

## Deletion contract

- Deleting a holding sets both `deletedAt` and `updatedAt` to the deletion time and upserts that payload.
- Tombstoned rows remain in local and cloud storage. They are hidden from active UI and valuation.
- A client must never infer deletion because an ID is absent from another device's list.
- A client must never physically delete all cloud rows not present locally.
- Tombstone compaction requires a separate, future server policy with a retention period and proof that every device has observed the tombstone.

## Deterministic merge

For each holding ID:

1. Local-only and remote-only records are retained.
2. The conflict timestamp is `max(valid updatedAt ?? valid createdAt ?? 0, valid deletedAt ?? 0)`.
3. The record with the newer conflict timestamp wins as a complete payload.
4. At an exact timestamp tie, a tombstone wins over an active record.
5. At any other exact tie, the local payload wins, matching current Web behavior.
6. Winners with an older schema are upgraded to the current native schema before persistence or upload.
7. The merged full set is saved locally; only missing or changed winners need to be upserted remotely.

This is last-write-wins for a complete holding, not field-by-field or adjustment-array merging. Devices must assign a fresh `updatedAt` whenever user-visible holding content changes.

## Required Web migration

Implementation status (2026-08-28): completed in repository source, covered by `tests/holding-sync.test.cjs`, and deployed to production as Cloudflare Worker version `9efa3115-a007-4b38-876a-ed4b6642c08c`. The user reports that `supabase/schema.sql` has been applied. A disposable production holding completed the Web create/delete flow and remains in Supabase with matching `deletedAt`/`updatedAt` and `schemaVersion = 2`; the native client subsequently pulled that exact tombstone into account-scoped storage without displaying it.

Before the native client connects to production Supabase, update `public/app.js` so it:

1. Preserves records carrying `deletedAt` during local normalization.
2. Replaces physical local removal with a tombstone mutation.
3. Removes the `delete().not('id', 'in', ...)` remote cleanup in `pushCloudHoldings`.
4. Upserts tombstones exactly like active records.
5. Uses the deterministic merge rules above, including tombstone priority on ties.
6. Hides tombstones from active lists, totals, quote polling, and charts while retaining them for sync.

## Native boundaries

Implementation status (2026-08-28): the Google PKCE authentication service, Keychain session store, and Supabase REST holdings repository are implemented and covered by offline transport tests. `RootTabView` uses the real cloud repository, and the Web-to-iOS production tombstone pull has passed. Profile synchronization is a separate concern documented in `ios/Docs/PROFILE_SYNC_CONTRACT.md`.

- `AuthenticationSessionServing` owns Apple/Google sign-in, secure token storage, session restoration, refresh, and sign-out.
- `CloudHoldingRepository` owns Supabase row decoding and upserts. It deliberately exposes no physical-delete method.
- `ScopedHoldingRepository` stores guest holdings at the legacy path and each authenticated user's holdings in a separately encoded account directory.
- `HoldingSyncCoordinator` validates the current session, loads the account scope, optionally copies guest records, pulls remote records, applies `HoldingMerge`, saves the complete winner set locally, and upserts only the remote delta.
- A cloud pull failure must occur before local persistence. A remote upsert failure leaves the merged local state intact and reports a pending upload; the next sync recomputes the same delta from local and remote state.
- Guest records are never merged implicitly during sign-in. The caller must pass either `keepSeparate` or `copyIntoAccount`; copying preserves the guest source so deleting or replacing guest data requires a separate explicit action.
- Views do not call authentication, cloud, or storage boundaries directly. `AccountViewModel` owns presentation state and invokes the coordinator.
- A Supabase URL and anon key are public client configuration, but refresh/access tokens must be stored in Keychain rather than JSON or `UserDefaults`.
- The registered native callback is `pawfolio://auth/callback`; it must also appear verbatim in Supabase Authentication → URL Configuration → Redirect URLs.
