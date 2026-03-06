# Repository Guidelines

## Project Structure & Module Organization
`src/` contains the TypeScript frontend loaded by Vite. The main UI lives in `src/main.ts`, Tauri bridge calls live in `src/api.ts`, shared frontend types live in `src/types.ts`, and styles/assets live under `src/styles.css` and `src/assets/`.

`src-tauri/` contains the desktop shell. Rust entrypoints are `src-tauri/src/main.rs` and `src-tauri/src/lib.rs`; app config, capabilities, and icons live under `src-tauri/tauri.conf.json`, `src-tauri/capabilities/`, and `src-tauri/icons/`. Release helpers are in `scripts/` and CI automation is in `.github/workflows/`.

## Build, Test, and Development Commands
Run `npm install` once to install frontend and Tauri CLI dependencies.

- `npm run tauri dev` starts the desktop app in local development.
- `npm run build` runs `tsc` and produces the Vite frontend bundle.
- `npm run build:app` creates the packaged Tauri app bundle. ALWAYS run this when you finish working on a change.
- `npm run build:macos:unsigned` builds the app and creates unsigned `.dmg` and `.zip` artifacts in `dist-artifacts/`.
- `cargo test --manifest-path src-tauri/Cargo.toml` runs the Rust unit tests.
- `./scripts/ci/validate-version.sh v0.2.0` verifies version alignment across release files.

## Testing Guidelines
Rust tests are defined inline in `src-tauri/src/lib.rs` under `#[cfg(test)]`. Add focused unit tests for deep links, URL validation, preset normalization, and host restriction logic when touching that behavior. The repo does not currently include frontend test tooling, so at minimum smoke-test UI changes with `npm run tauri dev`.
