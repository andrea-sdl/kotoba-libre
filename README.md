# Kotoba Libre

Kotoba Libre is a macOS-native launcher and web wrapper for LibreChat, built with Swift Package Manager, AppKit, SwiftUI, and WebKit.

The app gives LibreChat a focused desktop shell with:

- Guided onboarding for first launch
- A native settings window for instance configuration, agents, and shortcuts
- Configurable app presence modes: dock only, dock + menu bar, or menu bar only
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
|   |-- KotobaLibreApp
|   |-- KotobaLibreCore
|   `-- KotobaLibreSelfTest
|-- docs
|   |-- architecture.md
|   |-- development.md
|   |-- release.md
|   `-- plans
|-- scripts
|   |-- build-app.sh
|   |-- create-unsigned-dmg.sh
|   |-- ci/semver-bump.sh
|   `-- ci/validate-version.sh
`-- VERSION
```

## Modules

- `Sources/KotobaLibreApp`
  Native macOS executable. Owns the app lifecycle, windows, onboarding flow, settings UI, shortcut registration, and embedded `WKWebView`.
- `Sources/KotobaLibreCore`
  Shared models and business logic: settings, preset normalization, deep links, URL validation, host restriction, import/export, and storage helpers.
- `Sources/KotobaLibreSelfTest`
  Runnable regression suite for core behavior in environments where `swift test` is not available.

## Developer Workflow

Build the project:

```bash
swift build
```

Run the self-test suite:

```bash
swift run KotobaLibreSelfTest
```

Run the native GUI smoke test against an isolated temporary app-data directory:

```bash
swift run KotobaLibreApp --smoke-test
```

Launch the app directly from SwiftPM:

```bash
swift run KotobaLibreApp
```

Build the distributable app bundle and unsigned artifacts:

```bash
./scripts/build-app.sh
```

Generated artifacts:

- `dist-artifacts/Kotoba Libre.app`
- `dist-artifacts/Kotoba Libre-unsigned.dmg`
- `dist-artifacts/Kotoba Libre-unsigned-app.zip`

## Key User Flows

### First launch

If no settings exist, the main window opens a two-step onboarding flow:

1. Enter the LibreChat base URL
2. Confirm or record the global launcher shortcut

After setup completes, Kotoba Libre saves configuration and opens the main web view in an `800x600` default window.

### Settings management

The settings window includes tabs for:

- Agents
- Settings
- Shortcuts
- About

The settings UI warns before you leave a tab with unsaved changes.

From the Settings tab, users can also choose whether Kotoba Libre appears:

- In both the Dock and the menu bar
- Only in the Dock
- Only in the menu bar

When the menu bar item is enabled, it includes actions for opening Settings, showing the LibreChat window, and quitting the app.

When host restriction is enabled and you change the configured LibreChat instance to a different host, Kotoba Libre re-validates saved agents, offers an export step first, and removes any incompatible agents after you confirm the change.

The Settings tab also includes a destructive reset action that clears config and returns the app to onboarding.

### Launcher

The launcher is a floating panel that:

- Opens with the configured global shortcut
- Lets the user pick a preset
- Passes prompt text into LibreChat URLs
- Falls back gracefully when no instance or presets are configured

## Deep Links

Kotoba Libre currently supports:

- `kotobalibre://open?url=<encoded_url>`
- `kotobalibre://preset/<presetId>?query=<encoded_query>`
- `kotobalibre://settings`
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
The release workflow is launched manually from the default branch, creates the release tag for the selected `patch` / `minor` / `major` bump, publishes only the unsigned DMG to GitHub Releases, and then advances `VERSION` to the next `-dev` version on the default branch.

## License

Kotoba Libre is licensed under the GNU General Public License v2.0. See [LICENSE](/Users/andreagrassi/Documents/GitHub/tauri-a8chat/LICENSE).

More detail:

- [Architecture](/Users/andreagrassi/WebstormProjects/toro-libre/docs/architecture.md)
- [Development](/Users/andreagrassi/WebstormProjects/toro-libre/docs/development.md)
- [Release](/Users/andreagrassi/WebstormProjects/toro-libre/docs/release.md)
