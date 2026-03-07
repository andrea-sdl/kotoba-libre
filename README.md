# Toro Libre

Toro Libre is a macOS-native launcher and web wrapper for LibreChat, built with Swift Package Manager, AppKit, SwiftUI, and WebKit.

The app gives LibreChat a focused desktop shell with:

- Guided onboarding for first launch
- A native settings window for instance configuration, agents, and shortcuts
- A Spotlight-style launcher opened through a global keyboard shortcut
- Deep links for opening settings, presets, and direct destinations
- JSON import/export for agent presets
- Unsigned `.app`, `.dmg`, and `.zip` packaging for internal distribution

## Current Stack

- Swift 6.2
- Swift Package Manager
- AppKit app lifecycle and window management
- SwiftUI for onboarding, settings, and launcher UI
- WebKit for the embedded LibreChat experience
- GitHub Actions for unsigned release automation

## Repository Layout

```text
.
|-- Package.swift
|-- Sources
|   |-- ToroLibreApp
|   |-- ToroLibreCore
|   `-- ToroLibreSelfTest
|-- docs
|   |-- architecture.md
|   |-- development.md
|   |-- release.md
|   `-- plans
|-- scripts
|   |-- build-app.sh
|   |-- create-unsigned-dmg.sh
|   `-- ci/validate-version.sh
`-- VERSION
```

## Modules

- `Sources/ToroLibreApp`
  Native macOS executable. Owns the app lifecycle, windows, onboarding flow, settings UI, shortcut registration, and embedded `WKWebView`.
- `Sources/ToroLibreCore`
  Shared models and business logic: settings, preset normalization, deep links, URL validation, host restriction, import/export, and storage helpers.
- `Sources/ToroLibreSelfTest`
  Runnable regression suite for core behavior in environments where `swift test` is not available.

## Developer Workflow

Build the project:

```bash
swift build
```

Run the self-test suite:

```bash
swift run ToroLibreSelfTest
```

Launch the app directly from SwiftPM:

```bash
swift run ToroLibreApp
```

Build the distributable app bundle and unsigned artifacts:

```bash
./scripts/build-app.sh
```

Generated artifacts:

- `dist-artifacts/Toro Libre.app`
- `dist-artifacts/Toro Libre-unsigned.dmg`
- `dist-artifacts/Toro Libre-unsigned-app.zip`

## Key User Flows

### First launch

If no settings exist, the main window opens a two-step onboarding flow:

1. Enter the LibreChat base URL
2. Confirm or record the global launcher shortcut

After setup completes, Toro Libre saves configuration and opens the main web view in an `800x600` default window.

### Settings management

The settings window includes tabs for:

- Agents
- Settings
- Shortcuts
- About

The Settings tab also includes a destructive reset action that clears config and returns the app to onboarding.

### Launcher

The launcher is a floating panel that:

- Opens with the configured global shortcut
- Lets the user pick a preset
- Passes prompt text into LibreChat URLs
- Falls back gracefully when no instance or presets are configured

## Deep Links

Toro Libre currently supports:

- `torolibre://open?url=<encoded_url>`
- `torolibre://preset/<presetId>?query=<encoded_query>`
- `torolibre://settings`
- `https://.../app/open?url=<encoded_url>`
- `https://.../app/preset/<presetId>?query=<encoded_query>`
- `https://.../app/settings`

See [docs/architecture.md](/Users/andreagrassi/WebstormProjects/toro-libre/docs/architecture.md) for behavior details.

## Data Storage

App data is stored under the user Application Support directory in:

- `settings.json`
- `presets.json`

The files are managed through `AppDataStore` and recreated automatically when needed.

## Releases

The canonical version lives in `VERSION`.

Validate the version before release:

```bash
./scripts/ci/validate-version.sh v0.1.0
```

Unsigned release automation is defined in `.github/workflows/release.yml`.

More detail:

- [Architecture](/Users/andreagrassi/WebstormProjects/toro-libre/docs/architecture.md)
- [Development](/Users/andreagrassi/WebstormProjects/toro-libre/docs/development.md)
- [Release](/Users/andreagrassi/WebstormProjects/toro-libre/docs/release.md)
