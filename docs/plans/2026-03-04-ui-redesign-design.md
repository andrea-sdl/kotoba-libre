# Archived UI Design Note

Last updated: March 8, 2026

This document previously described a visual redesign for a web-based settings shell that no longer exists in the repository.

## Superseded Context

The old design note assumed:

- TypeScript UI templates
- CSS-driven settings layout
- A Tauri-era application shell

Those assumptions are obsolete for the current codebase.

## Current Design Surface

The active UI is native and implemented with SwiftUI inside AppKit windows:

- First-run onboarding flow
- Settings tabs
- Shortcut setup and diagnostics
- Spotlight-style launcher panel

Relevant implementation files:

- [Views.swift](../../Sources/KotobaLibreApp/Views.swift)
- [WebViewControllers.swift](../../Sources/KotobaLibreApp/WebViewControllers.swift)
- [LauncherWindowController.swift](../../Sources/KotobaLibreApp/LauncherWindowController.swift)

## Canonical Replacements

- [docs/architecture.md](../architecture.md)
- [docs/development.md](../development.md)
- [README.md](../../README.md)
