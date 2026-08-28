# PawFolio native authentication setup

## Current implementation

- Bundle ID: `com.jiujiucat.pawfolio`
- OAuth callback: `pawfolio://auth/callback`
- Google OAuth uses Supabase PKCE through the system `ASWebAuthenticationSession` UI.
- Access and refresh tokens are stored only in Keychain.
- Sign in with Apple remains disabled until an Apple Developer Team is available.
- Production holdings sync remains deliberately paused until the Web tombstone release is deployed and smoke-tested.

No WebView, embedded Web page, JavaScript bridge, Google client secret, access token, or refresh token belongs in the app source.

## Required Supabase dashboard step

Open the existing project and go to:

`Authentication → URL Configuration → Redirect URLs`

Add this exact value and save it:

`pawfolio://auth/callback`

Do not replace the existing Website URL or remove existing Web redirect entries.

## Login verification

Verified successfully on 2026-08-28 using the iPhone 17 Pro simulator (iOS 26.4.1):

- Supabase opened Google authentication in the system authentication sheet.
- Google returned through `pawfolio://auth/callback` to PawFolio.
- PawFolio displayed an authenticated Google session while cloud sync stayed paused.
- A full process restart restored the session from Keychain.
- Sign-out cleared the session; a second process restart stayed signed out.

The simulator is intentionally signed out after this verification.

For future regression checks:

After the redirect is saved:

1. Build and launch PawFolio in an iOS simulator or on a signed device.
2. Open Account and choose Google.
3. Complete the system browser sheet and confirm it returns to PawFolio.
4. Confirm Account shows the Google email and the paused cloud-sync message.
5. Sign out, relaunch, and confirm the account does not restore.

The paused-sync message is expected. Enabling `SupabaseCloudHoldingRepository` is a separate step gated by the production Web deletion test documented in `SYNC_CONTRACT.md`.
