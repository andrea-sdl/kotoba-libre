# Kotoba Libre Plan

Last updated: March 8, 2026

This file is the lightweight product and engineering plan for the current native macOS implementation.

## Current Baseline

Kotoba Libre now ships as a Swift Package Manager app with:

- Native onboarding for first launch and config reset
- A tabbed settings window for instance configuration, agents, shortcuts, and app information
- A floating launcher panel driven by a global shortcut
- Embedded LibreChat web content through `WKWebView`
- JSON-backed settings and preset persistence
- Unsigned packaging and GitHub release automation

## Near-Term Priorities

1. Harden first-run and reset UX with broader manual smoke testing around permissions and launcher behavior.
2. Expand regression coverage in `KotobaLibreSelfTest` for onboarding-adjacent persistence and preset defaults.
3. Improve documentation and release confidence for internal distribution on fresh macOS machines.

## Medium-Term Opportunities

1. Add richer launcher ergonomics, such as recent prompts or preset search.
2. Improve settings validation feedback and permission guidance for global shortcuts.
3. Add a more formal automated UI verification path if the environment permits it.

## Constraints

- The project is macOS-only.
- The distribution flow is unsigned and not notarized.
- Local verification currently relies on `swift run KotobaLibreSelfTest` instead of `swift test` in this environment.

## Canonical References

- Product and technical overview: [README.md](./README.md)
- Architecture: [docs/architecture.md](./docs/architecture.md)
- Development workflow: [docs/development.md](./docs/development.md)
- Release workflow: [docs/release.md](./docs/release.md)
