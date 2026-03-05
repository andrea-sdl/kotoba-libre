# Toro Libre Tauri App Plan and Implementation Log

> Last updated: March 4, 2026

This document captures the complete implementation plan for a Tauri app that wraps `https://chat.example.com`, including current implementation status, decisions, and validation outcomes.

---

## 1. Product Goals

1. Deliver a native macOS-first desktop app for `chat.example.com` (private, proxied Toro Libre).
2. Register and handle app-trigger links.
3. Keep the app small, fast, and easy to distribute internally.
4. Provide local presets (agents/links) management.
5. Add a spotlight-like launcher opened by global shortcut with keyboard-first interaction.
6. Prefer SPA-style navigation for in-app route changes to avoid full reloads.

---

## 2. Finalized Decisions

- Shortcut default on macOS: `Alt+Shift+Space`
- Fallback non-mac default: `CommandOrControl+Shift+Space`
- Distribution target: unsigned internal build first.
- Launcher UX: native quick launcher window.
- Data persistence: local-only (no cloud sync) using JSON store files.
- Deep-link protocol: custom scheme `torolibre://...` with optional universal-link-ready parser path for HTTPS URLs.
- SPA behavior: attempt in-page navigation first, then native navigation fallback.

---

## 3. Current Architecture

### 3.1 High-level
- Backend (Rust/Tauri)
  - Manages windows, deep links, shortcut registration, and persistent storage commands.
  - Enforces destination policy (`https` + optional host restriction).
- Frontend (vanilla TS + Vite)
  - Serves local app shell and controls settings/launcher UIs.
  - Calls backend commands via `@tauri-apps/api/core`.

### 3.2 Windows
- `main` window
  - External window loads `https://chat.example.com`.
  - Always available for primary chat use.
- `settings` window
  - Local UI for app settings and preset management.
- `launcher` window
  - Lightweight frameless window hidden by default.
  - Opened by global shortcut.

### 3.3 Data Models
- `Preset`
  - `id`, `name`, `urlTemplate`, `kind`, `tags`, `createdAt`, `updatedAt`
- `AppSettings`
  - `globalShortcut`, `openInNewWindow`, `restrictHostToInstanceHost`, `defaultPresetId`

### 3.4 Storage
- Uses `tauri-plugin-store`.
- Files in app config dir:
  - `settings.json`
  - `presets.json`

---

## 4. Command Surface

- `get_settings() -> AppSettings`
- `save_settings(settings)`
- `list_presets() -> Preset[]`
- `upsert_preset(preset) -> Preset`
- `delete_preset(id)`
- `open_preset(id, query?)`
- `open_url(url)`
- `validate_url_template(urlTemplate)`
- `show_settings()`
- `hide_launcher()`

---

## 5. Deep-link & Opening Behavior

### 5.1 Accepted deep links
- `torolibre://open?url=<encoded>`
- `torolibre://preset/<presetId>?query=<encoded>`
- `torolibre://settings`

### 5.2 HTTPS-ready parsing (future universal-link path)
- `https://chat.example.com/app/open?url=...`
- `https://chat.example.com/app/preset/<id>?query=...`
- `https://chat.example.com/app/settings`

### 5.3 Single-instance handling
- Enabled via `tauri-plugin-single-instance`.
- Second invocation forwards deep-link payload to existing instance; does not spawn duplicate app.

---

## 6. Launcher Behavior (Implemented)

### 6.1 UX spec
- Text input for search.
- `Tab` moves focus from search input to list.
- First entry is selected by default.
- If search is empty and default preset exists, default preset is preselected.
- Up/down keys move selection.
- Enter opens selection.
- Escape closes launcher.
- Optional query input is appended dynamically to selected preset URL.

### 6.2 Dynamic query behavior
- If user pasted URL contains `{query}` placeholder, it is replaced.
- Otherwise `query` is added as URL parameter.

### 6.3 SPA navigation strategy
- For same-host `chat.example.com` destinations, script executed in webview tries:
  1. app-router push (defensive detection)
  2. `window.navigation.navigate(...)`
  3. `history.pushState(...) + popstate`
  4. fallback to `window.location.href`

---

## 7. Security / Policy

- URLs must be HTTPS.
- Optional restriction to host `chat.example.com` (default enabled).
- Settings include toggle to disable host restriction.
- Clipboard paste fallback added in local UI for reliability (`Cmd/Ctrl+V` handling).

---

## 8. Performance Target

- Keep frontend minimal (no framework overhead).
- Small static footprint by limiting dependencies.
- Keep windows lightweight and focused on essential interactions.
- Reuse existing `main` webview and avoid repeated reloads where possible.

---

## 9. Distribution Plan

### 9.1 Current scripts
- `npm run tauri build` via `build:app` (in `package.json`).
- `scripts/create-unsigned-dmg.sh` for local unsigned packaging.

### 9.2 Expected artifacts
- `.app`: `src-tauri/target/release/bundle/macos/Toro Libre.app`
- Optional DMG/ZIP from `create-unsigned-dmg.sh`.

### 9.3 Known environment issue
- On this environment, `npm run build:app` reaches DMG packaging and fails at `bundle_dmg.sh`.
- `npm run tauri build -- --bundles app` succeeds and produces the `.app` bundle.
- This is likely environment/tooling related rather than app-code-related.

---

## 10. Build and Validation Matrix

### 10.1 Commands to run
- Frontend compile: `npm run build`
- Full build: `npm run build:app`
- App-only bundle: `npm run tauri build -- --bundles app`
- Unit tests: `CARGO_HOME=/tmp/cargo-home cargo test --manifest-path src-tauri/Cargo.toml`

### 10.2 Current status
- Unit tests: passing.
- App bundle build: passing.
- DMG build path: environment-dependent failure at `bundle_dmg.sh`.

---

## 11. Implementation Status (Now)

### Completed
- Main chat embedding configured.
- Custom deep-link parser and command routing implemented.
- Preset CRUD + local persistence.
- Default preset setting in settings UI.
- Global shortcut registration and launcher window management.
- Spotlight-like launcher flow (keyboard-first).
- Query injection + fallback logic for URLs.
- SPA-first navigation attempt before fallback.
- Paste fallback for local inputs.
- Single-instance + settings menu item wiring.

### Pending / optional follow-ups
- macOS universal links end-to-end (associated domains + entitlements + infra config).
- Improve SPA router detection for specific chat.example.com internals if needed.
- Add installer profile and post-install docs for unsigned/internal distribution.
- Optional code cleanup pass with broader simplification if desired.

---

## 12. Files of interest

- `src-tauri/src/lib.rs`
- `src/main.ts`
- `src/api.ts`
- `src/types.ts`
- `src/styles.css`
- `src-tauri/tauri.conf.json`
- `scripts/create-unsigned-dmg.sh`
- `README.md`

---

