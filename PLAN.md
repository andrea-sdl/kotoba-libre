# Toro Libre Swift Rewrite Notes

Last updated: March 6, 2026

## Current Architecture

- `ToroLibreCore`
  - Shared data models
  - Settings and preset persistence
  - Deep-link parsing
  - URL validation and host restriction
  - Preset import/export helpers
  - Query template expansion
- `ToroLibreApp`
  - AppKit lifecycle and menu
  - SwiftUI settings, launcher, and first-run UI
  - `WKWebView` main window and secondary chat windows
  - Native global shortcut registration
  - Launch-at-login synchronization
- `ToroLibreSelfTest`
  - Runnable validation suite for the ported core logic

## Preserved Behavior

- `torolibre://open?url=...`
- `torolibre://preset/<presetId>?query=...`
- `torolibre://settings`
- Settings and presets JSON schema
- HTTPS-only destinations
- Optional host restriction tied to the configured instance URL
- Query placeholder replacement and `prompt`/`submit=true` fallback
- Launcher default preset behavior
- Same-host SPA-first navigation before full page load fallback

## Build and Packaging

- Development compile: `swift build`
- Local validation: `swift run ToroLibreSelfTest`
- App bundle + unsigned artifacts: `./scripts/build-app.sh`
- Release version source: `VERSION`

## Known Environment Note

- The current local Command Line Tools installation does not expose a usable SwiftPM test framework module (`Testing` or `XCTest`) to `swift test`.
- Because of that, this repo validates the migrated logic through `ToroLibreSelfTest` in this environment.
