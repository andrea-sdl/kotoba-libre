# Repository Guidelines

## Project Structure & Module Organization

Kotoba Libre is a macOS-only Swift Package Manager project.

- `Package.swift` defines three targets:
  - `KotobaLibreApp`: native desktop app
  - `KotobaLibreCore`: shared logic and persistence
  - `KotobaLibreSelfTest`: executable regression suite
- `Sources/KotobaLibreApp/` contains the AppKit lifecycle, SwiftUI screens, global shortcut integration, launcher panel, settings window, and WebKit controllers.
- `Sources/KotobaLibreCore/` contains shared models, URL and deep-link parsing, preset normalization, import/export, and file-backed settings storage.
- `Sources/KotobaLibreSelfTest/` contains the self-test executable used in place of `swift test`.
- `docs/` contains architecture, development, release, and archived planning notes.
- `scripts/` contains packaging and release helpers.
- `.github/workflows/release.yml` builds unsigned release artifacts on tags or manual dispatch.

## Build, Test, and Development Commands

- `swift build` compiles all targets for local development.
- `swift run KotobaLibreApp` launches the app directly from SwiftPM.
- `swift run KotobaLibreSelfTest` runs the regression suite for core behaviors.
- `./scripts/build-app.sh` builds the release executable, assembles `Kotoba Libre.app`, and creates unsigned `.dmg` and `.zip` artifacts in `dist-artifacts/`.
- `./scripts/ci/validate-version.sh v0.1.0` verifies that the requested version matches `VERSION`.

Always run `./scripts/build-app.sh` when you finish a code change.

## Testing Guidelines

- Add or update assertions in `Sources/KotobaLibreSelfTest/main.swift` whenever you touch deep links, URL validation, preset normalization, storage behavior, or host restriction logic.
- Smoke-test SwiftUI and AppKit changes locally with `swift run KotobaLibreApp` when practical.
- Prefer focused, behavior-oriented checks over broad snapshot-style assertions.

## UI & Platform Notes

- The app uses AppKit windows with SwiftUI content and WebKit embedding.
- First launch and config reset should route through the native onboarding flow.
- The main window defaults to `800x600`; avoid introducing docs or code that assume the older large-window defaults.
- Global shortcut capture and registration rely on Carbon and accessibility/input-monitoring behavior on macOS.

## Documentation Expectations

- Keep docs aligned with the current SwiftPM/AppKit/SwiftUI/WebKit stack.
- Do not reintroduce Tauri, Vite, Rust, or TypeScript references unless the codebase actually adds them back.
- Update `README.md` and any affected docs in `docs/` when changing app flows, build commands, or release behavior.
