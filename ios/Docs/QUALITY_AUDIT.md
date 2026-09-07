# PawFolio iOS architecture and quality audit

Last reviewed: 2026-09-03

## Architecture summary

- `App/RootTabView.swift` is the composition root. It creates authentication,
  account/profile synchronization, scoped holding storage, and the active
  `PortfolioViewModel`.
- `Features/` owns SwiftUI views and `@MainActor` observable view models. Views
  delegate persistence and network work rather than talking to Supabase or the
  Worker directly.
- `Domain/` contains the persisted `Holding` model and pure financial rules:
  valuation, position/rate mutations, grouping, reconciliation, and history
  reconstruction. This layer is covered by the SwiftPM test target.
- `Data/` implements local JSON storage, Keychain-backed sessions, Worker market
  data, disk caches, and Supabase REST repositories. Coordinators reconcile
  local-first state before uploading deltas.
- `Nvwa/` is a standalone Swift package for design tokens and reusable controls.
  PawFolio injects product-owned Remix icons into those controls.
- The Web app remains a separate client and behavior reference. Cross-platform
  compatibility is defined by the versioned holding payload and tombstones.

### Main data flows

1. Portfolio read/write: `PortfolioView` → `PortfolioViewModel` →
   `HoldingPositionAdjustment` / `HoldingRecordMutation` → scoped local JSON.
2. Market data: `PortfolioViewModel` → `CachedMarketQuoteRepository` →
   `LiveMarketDataClient` → Cloudflare Worker, with disk-cache fallback.
3. Holding sync: `AccountViewModel` → `HoldingSyncCoordinator` → local and
   Supabase repositories → `HoldingMerge` → local save → remote delta upsert.
4. Profile sync follows the same local/remote reconciliation shape through
   `ProfileSyncCoordinator` and `AccountProfileMerge`.

## Problem areas

### High priority

1. `PortfolioViewModel` can start untracked quote refresh tasks after a save.
   Multiple refreshes may interleave across suspension points, allowing an older
   response to overwrite a newer one and making `isRefreshingQuotes` inaccurate.
2. Portfolio derived state is recomputed repeatedly during one SwiftUI render.
   `openHoldings` sorts every time it is read; total value, profit, percentage,
   and interest repeat valuation work. Interest valuation sorts adjustment
   history, so the cost grows with both positions and historical edits.
3. `PortfolioHistoryBuilder` evaluates every holding at every chart sample and
   repeatedly walks adjustment arrays. Its effective complexity is roughly
   positions × samples × adjustments. Preserve the current algorithm until a
   benchmark fixture proves a replacement has identical endpoints and disclosure
   behavior.

### Maintainability

1. The largest feature files are too broad: `HoldingEditorView.swift` (~1,460
   lines), `PortfolioView.swift` (~1,300), and `HoldingDetailView.swift` (~1,180).
   State, formatting, routing, and component rendering are coupled in single
   files, increasing merge conflicts during the active Figma migration.
2. `HoldingDraft` validation is private to a large view file. Domain-affecting
   form rules such as zero-APR support therefore lack direct unit tests.
3. `PortfolioViewModel` reads `Date`, `UserDefaults.standard`, and creates
   unstructured tasks directly. Injecting a clock, preferences store, and refresh
   scheduler would make failure/retry and concurrency behavior deterministic.
4. `loadIfNeeded` marks the model loaded before `reload` succeeds. A transient
   initial storage error requires an explicit reload instead of retrying when the
   view task is recreated.
5. UI strings remain hardcoded and there is no String Catalog. This is already a
   release limitation, but extracting giant views before localization will avoid
   duplicating localization work.

### Duplication addressed in this audit

The holdings and profile Supabase repositories each contained their own copy of
PostgREST URL construction, headers, access-token lookup, one-time 401 refresh,
retry, status validation, and error-payload decoding. They now share the private
`SupabaseRESTClient`; repository protocols, public initializers, table payloads,
and retry behavior are unchanged.

## Refactoring strategy

1. Keep domain behavior locked by parity tests. Add characterization tests before
   moving validation or changing history/valuation iteration.
2. Make quote refresh single-flight: retain and cancel or coalesce the active
   task, attach a generation identifier, and only publish the latest result.
3. Introduce one immutable portfolio snapshot per state/time input. Compute
   sorted open holdings and each holding's metrics once, then derive totals,
   groups, and row models from that snapshot.
4. Benchmark history construction with large adjustment fixtures. If warranted,
   pre-sort adjustments and advance cursors across the ordered timeline instead
   of reducing the full arrays for every point.
5. Split the three large Portfolio views by route/component only after the
   current Figma work settles. Keep orchestration in the parent and pass immutable
   render models plus narrow actions to children.
6. Extract editor draft validation into a pure Domain type and add boundary tests
   before moving any field or changing persisted payloads.

## Verification guardrails

- Preserve `schemaVersion = 2`, `deletedAt` tombstones, conflict timestamps, and
  existing Supabase row/query shapes.
- Keep every `withTaskGroup` child result as a named `Sendable` type; tuple child
  results trigger an optimized-build runtime crash on the current toolchain.
- Run SwiftPM tests and the generic simulator `build-for-testing` after each
  meaningful slice. Run the named-simulator XCTest bundle when CoreSimulator is
  available.
