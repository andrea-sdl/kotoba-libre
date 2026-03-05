#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version-or-tag>" >&2
  exit 1
fi

expected_version="${1#v}"

if [[ ! "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid semantic version: '${expected_version}'" >&2
  exit 1
fi

package_version="$(node -p "require('./package.json').version")"
cargo_version="$(
  awk '
    /^\[package\]/ { in_package = 1; next }
    /^\[/ { in_package = 0 }
    in_package && $1 == "version" {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' src-tauri/Cargo.toml
)"
tauri_version="$(node -p "require('./src-tauri/tauri.conf.json').version")"

if [[ -z "${cargo_version}" ]]; then
  echo "Could not read package version from src-tauri/Cargo.toml" >&2
  exit 1
fi

declare -a mismatches=()

if [[ "${package_version}" != "${expected_version}" ]]; then
  mismatches+=("package.json: expected '${expected_version}', found '${package_version}'")
fi

if [[ "${cargo_version}" != "${expected_version}" ]]; then
  mismatches+=("src-tauri/Cargo.toml: expected '${expected_version}', found '${cargo_version}'")
fi

if [[ "${tauri_version}" != "${expected_version}" ]]; then
  mismatches+=("src-tauri/tauri.conf.json: expected '${expected_version}', found '${tauri_version}'")
fi

if (( ${#mismatches[@]} > 0 )); then
  echo "Version mismatch detected:" >&2
  printf '%s\n' "${mismatches[@]}" >&2
  exit 1
fi

echo "Version check passed for ${expected_version}"
