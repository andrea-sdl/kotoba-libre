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
- Dock/menu bar visibility mode switching
- Menu bar status item actions
- Main web content window
- Popup web windows created by LibreChat flows, even when those popup windows navigate to another HTTPS host
- Settings window
- Launcher panel
- Voice launcher mode
- Onboarding flow
- Global shortcut capture and registration
- Launch-at-login integration

The UI stack is mixed by design:

- AppKit manages windows, menus, and system integration
- SwiftUI renders onboarding, settings, sheets, and launcher content with native Glass surfaces
- WebKit renders LibreChat content inside `WKWebView`
- Top-level `WKWebView` navigations add `X-Kotoba-Libre: Kotoba Libre/<version>` so the site can detect the embedded desktop app build
- When enabled in Instance Settings, external-host login redirects can be handed to the default browser, but that flow depends on the browser extension redirecting the completed auth back to `kotobalibre://...`
- The Chrome helper preserves optional host ports in that redirect, so local HTTPS setups like `localhost:3000` keep working
- Likely OAuth popup flows can be promoted into `ASWebAuthenticationSession` when their redirect URI returns through `kotobalibre://...`, otherwise they fall back to the external browser instead of staying trapped in `WKWebView`
- Popup-based passkey and security-key login can use build-configured `webcredentials` associated domains
- Passkey or FIDO/security-key prompts are still not supported when the login flow stays inside the main embedded Swift window

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
- Uses a `900x660` default size after onboarding completes
- Can open LibreChat home or route directly to a destination

### Settings window

- Separate management surface for agents, instance settings, system settings, shortcuts, and about information
- Hidden instead of destroyed when closed
- Used after onboarding for ongoing configuration
- Warns before switching tabs when the current page has unsaved changes

### Launcher panel

- Floating `NSPanel`
- Opened by the configured text shortcut or voice shortcut
- Keeps the launcher panel frontmost without surfacing the main window until a submission opens a destination
- Reuses one controller for a text prompt mode and a persistent voice mode
- Lets the user pick a preset from a compact glass selector and submit prompt text or spoken transcription
- Restores the previously frontmost app after launcher-driven navigation finishes

## App Presence Modes

Kotoba Libre persists one app visibility mode in settings:

- Dock only
- Dock and menu bar
- Menu bar only

When the menu bar item is enabled, it provides commands for:

- Showing the LibreChat window
- Opening Settings
- Quitting the app

The Dock icon is controlled through the app activation policy so switching modes takes effect without changing the rest of the window model.

## Configuration Flow

### First launch

If `settings.json` does not exist or does not contain an instance URL:

1. The app boots the main window
2. The main window renders the onboarding flow
3. The user sees a welcome step that explains Kotoba Libre as a macOS wrapper for LibreChat web apps
4. The user enters the LibreChat base URL
5. The user reviews optional voice permissions
6. The user confirms setup and the app saves settings before opening the main web view

### Reset

The System tab exposes a reset action with confirmation.

When the configured LibreChat host changes while host restriction is enabled, the app re-validates saved agents against the new host, offers export before save, and removes incompatible agents once the user confirms the change.

Reset clears:

- `settings.json`
- `presets.json`
- In-memory settings and preset state

After reset, the app returns to onboarding.

## Global Shortcut Strategy

Global shortcut registration is handled by `GlobalShortcutRegistrar`.

Current behavior:

- Registers separate global shortcuts for the text launcher, voice launcher, and main app window only after onboarding saves an instance URL
- Tries Carbon hotkeys first
- Uses an event-tap-only path for shortcuts that include `Fn`
- Installs an event tap when permissions allow
- Falls back to event-tap-only registration when Carbon registration fails
- Surfaces diagnostics for backend choice and permission state

## Voice Mode

Voice mode is built on native Apple microphone capture plus speech transcription.

- Opening the voice shortcut shows the launcher in voice presentation mode
- The panel stays visible until the user clicks Cancel or presses the voice shortcut again
- Pressing the voice shortcut a second time finalizes transcription and routes the resulting prompt through the same preset-opening path used by the text launcher
- The show-window shortcut toggles the main window without opening the launcher
- The System tab exposes both microphone and speech-recognition permission state because voice mode needs both

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
- `kotobalibre://<instance-host>/oauth/openid/callback?...`
- `/app/open?url=...`
- `/app/preset/<presetId>?query=...`
- `/app/settings`

When another app opens a plain `https://...` URL with Kotoba Libre, the app treats it as a direct in-app navigation only if the host matches the configured LibreChat instance host.

The shared parsing logic lives in `KotobaLibreCore`.
OpenID callback URLs that arrive as `kotobalibre://<instance-host>/oauth/openid/callback?...` are normalized back to their HTTPS equivalent before the app routes them.
