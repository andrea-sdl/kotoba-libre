# Repository Guidelines

## Project Structure & Module Organization

Toro Libre is a macOS-only Swift Package Manager project.

- `Package.swift` defines three targets:
  - `ToroLibreApp`: native desktop app
  - `ToroLibreCore`: shared logic and persistence
  - `ToroLibreSelfTest`: executable regression suite
- `Sources/ToroLibreApp/` contains the AppKit lifecycle, SwiftUI screens, global shortcut integration, launcher panel, settings window, and WebKit controllers.
- `Sources/ToroLibreCore/` contains shared models, URL and deep-link parsing, preset normalization, import/export, and file-backed settings storage.
- `Sources/ToroLibreSelfTest/` contains the self-test executable used in place of `swift test`.
- `docs/` contains architecture, development, release, and archived planning notes.
- `scripts/` contains packaging and release helpers.
- `.github/workflows/release.yml` builds unsigned release artifacts on tags or manual dispatch.

## Build, Test, and Development Commands

- `swift build` compiles all targets for local development.
- `swift run ToroLibreApp` launches the app directly from SwiftPM.
- `swift run ToroLibreSelfTest` runs the regression suite for core behaviors.
- `./scripts/build-app.sh` builds the release executable, assembles `Toro Libre.app`, and creates unsigned `.dmg` and `.zip` artifacts in `dist-artifacts/`.
- `./scripts/ci/validate-version.sh v0.1.0` verifies that the requested version matches `VERSION`.

Always run `./scripts/build-app.sh` when you finish a code change.

## Testing Guidelines

- Add or update assertions in `Sources/ToroLibreSelfTest/main.swift` whenever you touch deep links, URL validation, preset normalization, storage behavior, or host restriction logic.
- Smoke-test SwiftUI and AppKit changes locally with `swift run ToroLibreApp` when practical.
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
