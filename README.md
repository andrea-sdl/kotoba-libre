# Kotoba Libre

Kotoba Libre turns LibreChat into a focused Mac app.

The goal is simple: make LibreChat feel like a first-class desktop tool instead of a tab you keep losing. Kotoba Libre gives you a Spotlight-style command bar, voice entry, fast preset recall, and native window controls in a small macOS wrapper built with Swift, AppKit, SwiftUI, and WebKit.

## Why Kotoba Libre

LibreChat is powerful, but the browser workflow is easy to interrupt. Kotoba Libre keeps your instance close at hand, makes your favorite agents instantly recallable, and gives you dedicated shortcuts for typing, speaking, or showing the full app window without breaking flow.

## Highlights

- Spotlight-style launcher that is always one shortcut away
- Dedicated voice mode with animated listening state and Apple speech transcription
- Separate show/hide window shortcut for bringing the main app forward without opening the launcher
- Fast saving of agents and model links as presets so you can recall them in seconds
- Native-feeling experience around a live WebKit session, without the usual browser-tab reload dance, and with a small app footprint
- Menu bar only, Dock only, or hybrid presence modes depending on how visible you want the app to be
- Native onboarding, settings, popup handling, and deep links tailored for LibreChat

## Install

Download the latest build from the [GitHub Releases page](https://github.com/andrea-sdl/toro-libre/releases/latest).

Kotoba Libre currently ships as an unsigned, non-notarized macOS app. That means macOS will likely warn you the first time you open it. This is expected for the current release flow.

1. Download `Kotoba Libre-unsigned.dmg` from the latest release.
2. Drag `Kotoba Libre.app` into `/Applications`.
3. Open the app once.
4. If macOS blocks it, Control-click the app in Finder, choose `Open`, and confirm the prompt.
5. If macOS still refuses to launch it, open `System Settings > Privacy & Security`, find the blocked-app message for Kotoba Libre, and click `Open Anyway`.
6. If the quarantine flag still sticks, run:

```bash
xattr -dr com.apple.quarantine "/Applications/Kotoba Libre.app"
```

### Requirements

- macOS 26+

## What You Get

### Always-ready launcher

Kotoba Libre opens a floating Spotlight-like bar from a global shortcut, stays on top while you choose an agent or type a prompt, and launches into LibreChat only when you submit.

### Voice mode

Voice mode uses its own shortcut and its own launcher surface. It starts listening immediately, shows live animated feedback, and sends the finished transcript to the selected agent when you trigger the shortcut again.

### Show or hide the main app window

You also get a dedicated shortcut for the main window itself. Use it when you want the full LibreChat interface right away, then hide it again with the same shortcut when you are done.

### Presets and saved agents

When you are on an agent detail page inside LibreChat, Kotoba Libre can save that agent directly into the launcher list. It can also detect compatible model URLs and save them as Link presets, so the things you use most stay easy to recall.

### Fast native wrapper

Kotoba Libre keeps the desktop shell native and lightweight. Launcher interactions, settings, and window management happen in native macOS UI, while the embedded LibreChat session stays in place so your workflow avoids the usual browser-tab reload dance and the weight of a big cross-platform runtime.

## Current Stack

- Swift 6.2
- macOS 26+
- Swift Package Manager
- AppKit app lifecycle and window management
- SwiftUI with native Glass effects for onboarding, settings, sheets, and launcher UI
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

## Build From Source

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

Enable popup-based passkey and security-key support for specific relying-party domains:

```bash
KOTOBA_ASSOCIATED_DOMAINS="chat.example.com,login.example.com" ./scripts/build-app.sh
```

Those entries are normalized to `webcredentials:` entitlements at packaging time. They only help when the LibreChat login flow opens in a popup that Kotoba Libre can route through its popup and browser-backed auth handling, and arbitrary runtime instance URLs still cannot all be supported by one unsigned build.

## Known Limitation

If your LibreChat login flow requires a passkey or FIDO or security key and stays inside the main embedded Swift window, Kotoba Libre does not support that flow yet. The supported path today is for the login flow to open in a popup, where Kotoba Libre can route the authentication request through its popup and browser-backed auth handling.

Generated artifacts:

- `dist-artifacts/Kotoba Libre.app`
- `dist-artifacts/Kotoba Libre-unsigned.dmg`
- `dist-artifacts/Kotoba Libre-unsigned-app.zip`

## Key User Flows

### First launch

If no settings exist, the main window opens a four-step onboarding flow:

1. Start with a welcome screen that explains Kotoba Libre as a macOS wrapper for LibreChat web apps
2. Enter the LibreChat base URL
3. Review optional voice permissions
4. Confirm the setup and open LibreChat

The onboarding window opens as a compact wizard with focused steps, product context up front, inline URL validation, and default keyboard actions so first-run setup stays quick without needing an internal scroll area.

After setup completes, Kotoba Libre saves configuration, enables the app-wide shortcuts, and opens the main web view in a `900x660` default window.

### Settings management

The settings window includes tabs for:

- Agents
- Settings
- System
- Shortcuts
- About

The native settings, onboarding, add-agent sheet, and launcher surfaces use the recent macOS Glass APIs so the desktop chrome stays visually consistent across the app.

The settings UI warns before you leave a tab with unsaved changes.

When the embedded web view is on an agent detail page, the titlebar button can save that agent directly into the launcher list. The same button also detects `/c/new` model URLs such as `...?endpoint=anthropic&model=claude-opus-4-6` and offers to save them as Link presets.

From the System tab, users can also choose whether Kotoba Libre appears:

- In both the Dock and the menu bar
- Only in the Dock
- Only in the menu bar

When the menu bar item is enabled, it includes actions for opening Settings, showing the LibreChat window, and quitting the app.

The Shortcuts tab manages three separate shortcuts:

- Text launcher, which defaults to `Ctrl+Option+Space`
- Voice launcher, which defaults to `Ctrl+Option+V`
- Show app window, which defaults to `Ctrl+Option+K`

The System tab also includes microphone and speech-recognition permission status, debug logging, and a destructive reset action that clears config and returns the app to onboarding.

When host restriction is enabled and you change the configured LibreChat instance to a different host, Kotoba Libre re-validates saved agents, offers an export step first, and removes any incompatible agents after you confirm the change.

### Launcher

The launcher is a floating panel that:

- Opens with the configured global shortcut after onboarding is complete
- Stays in front by itself instead of surfacing the main LibreChat window until a launch is submitted
- Lets the user pick an agent from a styled glass selector
- Passes prompt text into LibreChat URLs
- Falls back gracefully when no instance or presets are configured

Voice mode adds a second floating launcher that:

- Opens with its own dedicated shortcut after onboarding is complete
- Starts recording immediately with an animated listening indicator instead of a text field
- Keeps the panel visible until you click Cancel or press the voice shortcut again
- Finishes transcription and sends the spoken prompt to the selected agent when you trigger the shortcut again

The main app window can also be surfaced directly with its own shortcut:

- Defaults to `Ctrl+Option+K`
- Shows the main Kotoba Libre window after onboarding without opening the launcher
- Hides the main window again when you trigger it a second time

## Deep Links

Kotoba Libre currently supports:

- `kotobalibre://open?url=<encoded_url>`
- `kotobalibre://preset/<presetId>?query=<encoded_query>`
- `kotobalibre://settings`
- `kotobalibre://<instance-host>/oauth/openid/callback?<query>`
- `https://.../app/open?url=<encoded_url>`
- `https://.../app/preset/<presetId>?query=<encoded_query>`
- `https://.../app/settings`

See [docs/architecture.md](docs/architecture.md) for behavior details.

### Chrome Extension Helper

Load the unpacked Chrome extension from `scripts/chrome-extension/kotobalibre-openid-callback`.

The extension:

- Uses Chrome dynamic redirect rules so callback navigations can be caught before the page renders
- Keeps the content-script redirect as a fallback for already-loaded callback pages
- Uses the same icon artwork as Kotoba Libre
- Opens its settings page when you click the extension icon
- Stores the allowed hosts and callback path with Chrome sync storage
- Always redirects into the fixed `kotobalibre://` scheme
- Starts inactive on a fresh install and opens its settings page so each user can enter their own default config

To test it in Chrome:

1. Open `chrome://extensions`
2. Enable Developer mode
3. Click `Load unpacked`
4. Select `scripts/chrome-extension/kotobalibre-openid-callback`
5. When the extension opens its setup page, enter the host list and callback path you want to use
6. Retry the login flow

To create a distributable source zip for the extension:

```bash
./scripts/package-chrome-extension.sh
```

That writes `dist-artifacts/chrome-extension/kotobalibre-openid-callback.zip` with the extension files at the archive root, which is the shape you want for sharing or Chrome Web Store upload.

The release workflow also builds and publishes that extension zip alongside the unsigned app artifacts.

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

The release workflow is launched manually from the default branch, creates the release tag for the selected `patch`, `minor`, or `major` bump, publishes the unsigned DMG to GitHub Releases, and then advances `VERSION` to the next `-dev` version on the default branch.

## Third-Party Notices

The launcher glow effect in `Sources/KotobaLibreApp/Views.swift` is adapted from the MIT-licensed `IntelligenceGlow` reference implementation. Kotoba Libre does not include that package as a dependency.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the full attribution and license notice.

## License

Kotoba Libre is licensed under the GNU General Public License v2.0. See [LICENSE](LICENSE).

More detail:

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Release](docs/release.md)
