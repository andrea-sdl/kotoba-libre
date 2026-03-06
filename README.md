# Toro Libre (SwiftPM, macOS-native)

Native macOS wrapper for a self-hosted Toro Libre instance, built with Swift, AppKit, SwiftUI, WebKit, and `swift build`.

## Core Features

- Native macOS app lifecycle and windows
- Main webview for the remote Toro Libre instance
- Separate native settings and launcher windows
- Custom deep links:
  - `torolibre://open?url=<encoded_url>`
  - `torolibre://preset/<presetId>?query=<encoded>`
  - `torolibre://settings`
- Local preset management with JSON import/export
- Global shortcut launcher
- Same-host SPA-first navigation in the main webview, with full-load fallback
- Unsigned `.app`, `.dmg`, and `.zip` packaging for internal distribution

## Project Layout

- `Package.swift`: SwiftPM manifest
- `Sources/ToroLibreCore`: shared models, validation, deep-link, storage, and template logic
- `Sources/ToroLibreApp`: AppKit/SwiftUI/WebKit macOS app
- `Sources/ToroLibreSelfTest`: runnable self-test executable for the migrated core behaviors
- `scripts/build-app.sh`: release build + `.app` assembly + unsigned artifact packaging
- `scripts/create-unsigned-dmg.sh`: creates unsigned `.dmg` and `.zip` from the built app bundle

## Development

```bash
swift build
swift run ToroLibreSelfTest
```

To launch the debug executable directly from SwiftPM:

```bash
swift run ToroLibreApp
```

## Build (Unsigned Internal)

```bash
./scripts/build-app.sh
```

Artifacts:

- `dist-artifacts/Toro Libre.app`
- `dist-artifacts/Toro Libre-unsigned.dmg`
- `dist-artifacts/Toro Libre-unsigned-app.zip`

## Versioning

The canonical app version lives in `VERSION`.

Validate it before releasing:

```bash
./scripts/ci/validate-version.sh v0.1.0
```

## Automated Releases

The GitHub Actions workflow at `.github/workflows/release.yml`:

1. Validates the requested version against `VERSION`
2. Builds the release SwiftPM executable
3. Assembles the macOS `.app`
4. Packages unsigned `.dmg` and `.zip` artifacts
5. Publishes a GitHub release with checksums

## Data Storage

The Swift app uses fresh app-owned JSON files under the macOS Application Support directory:

- `settings.json`
- `presets.json`

## Notes

- This repo is now macOS-only.
- The app remains unsigned and not notarized, so Gatekeeper prompts are expected for internal distribution.
- The local validation runner is `swift run ToroLibreSelfTest`; `swift test` is not usable in the current Command Line Tools environment because the packaged test frameworks are unavailable there.
