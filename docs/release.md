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

## Local Packaging

Build the release executable, app bundle, and unsigned archives with:

```bash
./scripts/build-app.sh
```

You can also pass an explicit version:

```bash
./scripts/build-app.sh 0.1.0
```

The build script:

1. Builds `KotobaLibreApp` in release mode
2. Creates `dist-artifacts/Kotoba Libre.app`
3. Copies bundled resources, including the app icon
4. Writes `Info.plist`
5. Applies an ad-hoc signature
6. Creates unsigned `.dmg` and `.zip` artifacts

## Expected Artifacts

After a successful packaging run, expect:

- `dist-artifacts/Kotoba Libre.app`
- `dist-artifacts/Kotoba Libre-unsigned.dmg`
- `dist-artifacts/Kotoba Libre-unsigned-app.zip`

## GitHub Release Workflow

The workflow in `.github/workflows/release.yml` supports:

- Tag-triggered releases on `v*`
- Manual `workflow_dispatch` releases with version input

High-level flow:

1. Resolve version and tag metadata
2. Fail if the release already exists
3. Set up Xcode
4. Validate `VERSION`
5. Build unsigned artifacts
6. Generate SHA256 checksums
7. Create the tag for manual releases if needed
8. Publish the GitHub release

## Distribution Notes

- Artifacts are unsigned for real distribution purposes and not notarized.
- Gatekeeper prompts should be expected on machines that have not previously trusted the build.
- A future signed/notarized path can branch from the existing release workflow.
