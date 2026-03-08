# Architecture

Kotoba Libre is a native macOS desktop wrapper for LibreChat. The project is organized as a Swift Package Manager workspace with clear separation between shared logic and the AppKit host.

## Targets

### `KotobaLibreCore`

`KotobaLibreCore` contains the shared domain and infrastructure logic:

- `AppSettings`, `Preset`, and related models
- URL normalization and validation
- Host restriction enforcement
- Deep-link parsing
- Query expansion for preset templates
- JSON import/export helpers
- `AppDataStore` for file-backed persistence

This target is intentionally UI-free so behavior can be validated in the self-test executable.

### `KotobaLibreApp`

`KotobaLibreApp` is the native executable and owns:

- `NSApplication` bootstrap
- App menu and lifecycle
- Main web content window
- Settings window
- Launcher panel
- Onboarding flow
- Global shortcut capture and registration
- Launch-at-login integration

The UI stack is mixed by design:

- AppKit manages windows, menus, and system integration
- SwiftUI renders onboarding, settings, and launcher content
- WebKit renders LibreChat content inside `WKWebView`

### `KotobaLibreSelfTest`

`KotobaLibreSelfTest` is a standalone executable used to validate core behavior without relying on `swift test`.

It focuses on:

- Settings normalization
- Shortcut normalization
- Deep-link parsing
- URL policy enforcement
- Preset import/export compatibility
- Store persistence and reset behavior

## Window Model

Kotoba Libre uses three main native window types:

### Main window

- Hosts onboarding when no instance is configured
- Hosts the main `WKWebView` once setup is complete
- Uses an `800x600` default size
- Can open LibreChat home or route directly to a destination

### Settings window

- Separate management surface for agents, settings, shortcuts, and about information
- Hidden instead of destroyed when closed
- Used after onboarding for ongoing configuration
- Warns before switching tabs when the current page has unsaved changes

### Launcher panel

- Floating `NSPanel`
- Opened by the configured global shortcut
- Lets the user pick a preset and submit prompt text
- Hides on focus loss and restores the previously frontmost app

## Configuration Flow

### First launch

If `settings.json` does not exist or does not contain an instance URL:

1. The app boots the main window
2. The main window renders the onboarding flow
3. The user enters the LibreChat base URL
4. The user confirms or records the launcher shortcut
5. Settings are saved and the main web view opens

### Reset

The Settings tab exposes a reset action with confirmation.

When the configured LibreChat host changes while host restriction is enabled, the app re-validates saved agents against the new host, offers export before save, and removes incompatible agents once the user confirms the change.

Reset clears:

- `settings.json`
- `presets.json`
- In-memory settings and preset state

After reset, the app returns to onboarding.

## Global Shortcut Strategy

Global shortcut registration is handled by `GlobalShortcutRegistrar`.

Current behavior:

- Tries Carbon hotkeys first
- Installs an event tap when permissions allow
- Falls back to event-tap-only registration when Carbon registration fails
- Surfaces diagnostics for backend choice and permission state

This design keeps common shortcuts working while still supporting cases that need Accessibility or Input Monitoring.

## Navigation Model

Kotoba Libre opens URLs in one of two ways:

- Same-host LibreChat URLs go into the embedded web view
- Other hosts open externally in the default browser

When possible, the app prefers SPA-style navigation for same-host LibreChat routes and falls back to full page loads when necessary.

## Persistence

Configuration is stored in the user Application Support directory under the app-specific config folder.

Files:

- `settings.json`
- `presets.json`

`AppDataStore` owns reading, writing, exporting, and reset cleanup.

## Deep Links

Supported custom-scheme and HTTPS-mapped routes include:

- `kotobalibre://open?url=...`
- `kotobalibre://preset/<presetId>?query=...`
- `kotobalibre://settings`
- `/app/open?url=...`
- `/app/preset/<presetId>?query=...`
- `/app/settings`

The shared parsing logic lives in `KotobaLibreCore`.
