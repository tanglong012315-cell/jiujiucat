# PawFolio versioning

Current release: **v1.1.0 (build 1)**

## Version fields

- Release names use `vMAJOR.MINOR.PATCH`, for example `v1.1.0`.
- Xcode stores the value without the `v` prefix in `MARKETING_VERSION`.
  `Info.plist` reads it through `CFBundleShortVersionString`.
- `CURRENT_PROJECT_VERSION` supplies `CFBundleVersion`, the App Store build
  number. It is independent from the release version and must be unique for each
  uploaded build of the same release.
- `Holding.schemaVersion`, cache-envelope versions, versioned filenames, Swift
  tools versions, API query cache-busters, and Asset Catalog `version` fields are
  technical compatibility values. Do not change them during a normal release
  version update.

## Release-number policy

- PATCH: compatible bug fixes, performance work, or internal refactoring.
- MINOR: backward-compatible user-facing functionality.
- MAJOR: an intentionally incompatible product, API, or persisted-data change.
- Pre-release names may use SemVer suffixes such as `1.2.0-beta.1`. Confirm App
  Store version-field compatibility before using a new suffix format.

The version supplied by the user is authoritative. Do not infer or automatically
bump a release version from commit contents.

## Update checklist

When the user supplies the next release version:

1. Set both PawFolio target configurations' `MARKETING_VERSION` to the supplied
   value without the leading `v`.
2. Keep the existing build number unless the user supplies one. Before an App
   Store Connect upload, use a build number not already uploaded for that release.
3. Confirm the resolved app settings with `xcodebuild -showBuildSettings` and
   inspect `MARKETING_VERSION` plus `CURRENT_PROJECT_VERSION`.
4. Run the repository-required SwiftPM tests and simulator build.
5. Record the version and verification result in `ios/HANDOFF.md`.
6. Create a Git tag such as `v1.2.0` only when the user explicitly requests it
   and the intended release commit is known.
