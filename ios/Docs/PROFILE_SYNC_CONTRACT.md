# PawFolio native/Web profile sync contract

This file records the active shared Web/native profile behavior. Production Profile synchronization was enabled and verified in both directions on 2026-08-28; the SwiftUI app does not embed or depend on the website.

## Existing production shape

The Web client stores one row per authenticated user in `public.profiles`:

- `user_id uuid` is the primary key and must equal `auth.uid()`.
- `display_name text` is optional and is trimmed to at most 20 characters.
- `avatar text` is a closed, client-validated identifier.
- `updated_at timestamptz` is the last-write-wins timestamp.
- Row-level security allows users to read and write only their own row.

Profile sync is independent from holding sync. A profile failure must never change the holding synchronization state.

## Web avatar identifiers

The current Web whitelist accepts these face assets:

- `face:happy`
- `face:cute`
- `face:love`
- `face:thinking`
- `face:sleepy`
- `face:surprised`
- `face:crying`
- `face:angry`
- `face:horn`

It also accepts the nine cat-photo identifiers:

- `cat:puffy`
- `cat:nono`
- `cat:jiujiu`
- `cat:liz`
- `cat:pudding`
- `cat:zhezhe`
- `cat:coco`
- `cat:momo`
- `cat:bobo`

The matching JPEG files live under `public/avatars/` and `public/cats/`. Native must package approved copies in its Asset Catalog rather than loading the website or constructing arbitrary remote image paths.

## Native implementation

The native store now writes `LocalAccountProfile(schemaVersion: 2)` per account. It persists `updatedAtMilliseconds` and accepts only the shared `face:*`/`cat:*` whitelist. Existing schema-1 placeholder values migrate deterministically on decode: `snow` → `face:cute`, `pawBlue` → `face:happy`, `ginger` → `face:love`, `lilac` → `face:thinking`, `mocha` → `face:sleepy`, and `midnight` → `face:horn`. A migrated record without an edit keeps timestamp `0`, so it cannot create a missing remote row merely because the app was upgraded.

Implemented foundation:

1. All 18 approved Web images are packaged in `Assets.xcassets` and validated against the shared identifier enum.
2. `AccountProfileMerge` uses `updatedAtMilliseconds`; the newer complete record wins and an exact tie keeps local.
3. `CloudProfileRepository` and `SupabaseCloudProfileRepository` support REST reads, upserts, owner-key validation, timestamp conversion, and one-time 401 refresh/retry.
4. Display names are trimmed and limited to 20 characters; unknown remote avatars are rejected.
5. Offline tests cover migration, local/remote winners, ties, missing rows, invalid avatars, upsert payloads, and retry behavior.
6. `ProfileSyncCoordinator` fetches, reconciles, persists remote winners, and uploads only the remote delta. Failed uploads return a retryable pending state while preserving local data.
7. `AccountViewModel` accepts the coordinator as an optional dependency and exposes a separate profile-sync state. Tests prove profile failures do not change a successful holding-sync state.

`RootTabView` now creates one shared `UserDefaultsAccountProfileStore`, a `SupabaseCloudProfileRepository`, and a production `ProfileSyncCoordinator`. The same local store is supplied to the coordinator and `AccountViewModel`, so the UI and merge engine cannot diverge through separate caches.

## Production verification — 2026-08-28

1. The existing Web value was recorded as `Long` / `face:horn` before enabling writes.
2. The simulator had a newer `雪球` / `face:love` record. On first launch, last-write-wins correctly uploaded that native record to Supabase with an identical millisecond timestamp.
3. The Web editor then restored `Long` / `face:horn`, creating a newer remote timestamp. After normal session refresh, native pulled the complete remote record without uploading a redundant change.
4. A second terminate/relaunch preserved `Long` / `face:horn`, the Keychain session, and the independent successful holding-sync state.
5. The Account footer now reports live Profile synchronization state. The old absolute “不会上传到 Supabase” copy was removed from the local-only fallback.
6. All 104 named-simulator XCTest cases passed after production wiring; SwiftPM tests and the normally signed simulator build also passed.

Manual retry now asks the authentication service for a current session before synchronizing. This permits the service to refresh an expired access token instead of requiring an app relaunch.

## Privacy

- UI receives only the ViewModel's display name, masked account label, provider label, and validated avatar.
- Never store access tokens, refresh tokens, or a full holdings payload in the profile store.
- Do not log or persist the full email outside the existing Keychain session record.
