# Release

Kotoba Libre currently ships unsigned macOS artifacts for internal distribution.

## Version Source

The canonical version lives in:

- `VERSION`

Before releasing, validate the requested version:

```bash
./scripts/ci/validate-version.sh v0.1.0
```

The script accepts either `0.1.0` or `v0.1.0` and fails if `VERSION` does not match.

Version bump math for the release workflow lives in:

- `scripts/ci/semver-bump.sh`

After each automated release, the default branch advances to the next patch development version with a `-dev` suffix. Example:

- Release `0.2.0`
- Default branch becomes `0.2.1-dev`

## Local Packaging

Build the release executable, app bundle, and unsigned archives with:

```bash
./scripts/build-app.sh
```

You can also pass an explicit version:

```bash
./scripts/build-app.sh 0.1.0
```

For popup-based passkey and security-key login support, package with the relying-party hosts declared up front:

```bash
KOTOBA_ASSOCIATED_DOMAINS="chat.example.com,login.example.com" ./scripts/build-app.sh
```

The build script turns those entries into `webcredentials:` associated domains before signing the app bundle. That packaging only helps when the login flow opens in a popup. Passkey or FIDO/security-key prompts that stay inside the main embedded Swift window are still not supported.

The build script:

1. Builds `KotobaLibreApp` in release mode
2. Creates `dist-artifacts/Kotoba Libre.app`
3. Copies bundled resources, including the app icon
4. Writes `Info.plist`
5. Applies an ad-hoc signature, optionally including generated `webcredentials` associated-domain entitlements
6. Creates unsigned `.dmg` and `.zip` app artifacts
7. Packages the Chrome and Firefox browser extension zips into `dist-artifacts/chrome-extension/` and `dist-artifacts/firefox-extension/`

## Expected Artifacts

After a successful packaging run, expect:

- `dist-artifacts/Kotoba Libre.app`
- `dist-artifacts/Kotoba Libre-unsigned.dmg`
- `dist-artifacts/Kotoba Libre-unsigned-app.zip`
- `dist-artifacts/chrome-extension/kotobalibre-openid-callback.zip`
- `dist-artifacts/firefox-extension/kotobalibre-openid-callback.zip`

## GitHub Release Workflow

The workflow in `.github/workflows/release.yml` supports:

- Manual `workflow_dispatch` releases from the default branch
- A required bump choice: `patch`, `minor`, or `major`
- Automatic release commit + tag creation
- Automatic post-release bump to the next patch `-dev` version
- Publishing the unsigned DMG plus the Chrome and Firefox extension zips to the GitHub release

High-level flow:

1. Verify the workflow is running from the default branch
2. Compute the release version from the selected bump and current `VERSION`
3. Fail if the tag or GitHub release already exists
4. Commit `VERSION=<release version>` and create `v<release version>`
5. Build unsigned app artifacts plus the Chrome and Firefox browser extension zips
6. Commit `VERSION=<next patch>-dev` locally on top of the release commit
7. Push the branch update and the release tag
8. Publish the GitHub release with the unsigned DMG and both browser extension zips

## Distribution Notes

- Artifacts are unsigned for real distribution purposes and not notarized.
- Gatekeeper prompts should be expected on machines that have not previously trusted the build.
- A future signed/notarized path can branch from the existing release workflow.
