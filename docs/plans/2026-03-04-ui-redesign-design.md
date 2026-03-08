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

- [Views.swift](/Users/andreagrassi/WebstormProjects/toro-libre/Sources/KotobaLibreApp/Views.swift)
- [WebViewControllers.swift](/Users/andreagrassi/WebstormProjects/toro-libre/Sources/KotobaLibreApp/WebViewControllers.swift)
- [LauncherWindowController.swift](/Users/andreagrassi/WebstormProjects/toro-libre/Sources/KotobaLibreApp/LauncherWindowController.swift)

## Canonical Replacements

- [docs/architecture.md](/Users/andreagrassi/WebstormProjects/toro-libre/docs/architecture.md)
- [docs/development.md](/Users/andreagrassi/WebstormProjects/toro-libre/docs/development.md)
- [README.md](/Users/andreagrassi/WebstormProjects/toro-libre/README.md)
