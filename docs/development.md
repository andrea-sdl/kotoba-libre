# Development

This project is a macOS-only Swift Package Manager application. There is no frontend bundler, no Tauri layer, and no Rust target in the current repository.

## Requirements

- macOS
- Xcode / Apple toolchain with Swift 6.2 support
- A local environment that can build AppKit, SwiftUI, and WebKit targets

## Primary Commands

Build all targets:

```bash
swift build
```

Run the native app:

```bash
swift run KotobaLibreApp
```

Run the regression suite:

```bash
swift run KotobaLibreSelfTest
```

Run the native GUI smoke test:

```bash
swift run KotobaLibreApp --smoke-test
```

Build the distributable app and unsigned archives:

```bash
./scripts/build-app.sh
```

## Day-to-Day Workflow

1. Make code changes in `Sources/`.
2. Run `swift run KotobaLibreSelfTest` after touching core behavior.
3. Run `swift run KotobaLibreApp --smoke-test` for an automated native UI smoke test.
4. Run `swift run KotobaLibreApp` when you need a manual UI or system-integration check.
5. Run `./scripts/build-app.sh` before finishing work.

## Where To Make Changes

### App lifecycle and orchestration

- `Sources/KotobaLibreApp/AppDelegate.swift`
- `Sources/KotobaLibreApp/AppController.swift`

### Native UI

- `Sources/KotobaLibreApp/Views.swift`
- `Sources/KotobaLibreApp/SettingsWindowController.swift`
- `Sources/KotobaLibreApp/LauncherWindowController.swift`
- `Sources/KotobaLibreApp/WebViewControllers.swift`

### Shared behavior and storage

- `Sources/KotobaLibreCore/KotobaLibreCore.swift`
- `Sources/KotobaLibreCore/AppDataStore.swift`

### Shortcut integration

- `Sources/KotobaLibreApp/GlobalShortcutRegistrar.swift`

### Regression checks

- `Sources/KotobaLibreSelfTest/main.swift`

## Testing Guidance

Use `KotobaLibreSelfTest` as the first line of regression coverage for:

- Deep-link parsing
- URL validation
- Host restriction changes
- Preset normalization
- Storage and reset behavior

Manual smoke testing is especially important when changing:

- Onboarding
- Global shortcut capture
- Permission prompts
- Window sizing and focus
- Launcher behavior
- Web navigation behavior

## Documentation Rule

If you change:

- Build commands
- App flows
- Window behavior
- Release packaging
- Storage format

update the docs in the same change.

Recommended docs to review:

- [README.md](/Users/andreagrassi/WebstormProjects/toro-libre/README.md)
- [docs/architecture.md](/Users/andreagrassi/WebstormProjects/toro-libre/docs/architecture.md)
- [docs/release.md](/Users/andreagrassi/WebstormProjects/toro-libre/docs/release.md)

## Notes About `swift test`

The current repo uses `swift run KotobaLibreSelfTest` instead of `swift test` as the practical local validation path for this environment. Keep the self-test maintained and fast.
