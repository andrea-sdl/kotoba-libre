#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version-or-tag>" >&2
  exit 1
fi

expected_version="${1#v}"
current_version="$(tr -d '[:space:]' < VERSION)"

if [[ ! "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid semantic version: '${expected_version}'" >&2
  exit 1
fi

if [[ "${current_version}" != "${expected_version}" ]]; then
  echo "Version mismatch detected: VERSION expected '${expected_version}', found '${current_version}'" >&2
  exit 1
fi

echo "Version check passed for ${expected_version}"
