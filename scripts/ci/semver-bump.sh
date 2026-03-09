#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <version-or-tag> <patch|minor|major> [--prerelease <label>]" >&2
  exit 1
}

if [[ $# -lt 2 || $# -gt 4 ]]; then
  usage
fi

version="${1#v}"
bump_kind="$2"
prerelease_label=""

if [[ $# -eq 4 ]]; then
  if [[ "$3" != "--prerelease" || -z "$4" ]]; then
    usage
  fi
  prerelease_label="$4"
fi

if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$ ]]; then
  echo "Invalid semantic version: '${version}'" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
existing_prerelease="${BASH_REMATCH[5]:-}"

next_major="${major}"
next_minor="${minor}"
next_patch="${patch}"

case "${bump_kind}" in
  patch)
    if [[ -z "${existing_prerelease}" ]]; then
      next_patch=$((patch + 1))
    fi
    ;;
  minor)
    next_minor=$((minor + 1))
    next_patch=0
    ;;
  major)
    next_major=$((major + 1))
    next_minor=0
    next_patch=0
    ;;
  *)
    echo "Unsupported bump kind: '${bump_kind}'. Expected patch, minor, or major." >&2
    exit 1
    ;;
esac

next_version="${next_major}.${next_minor}.${next_patch}"

if [[ -n "${prerelease_label}" ]]; then
  next_version="${next_version}-${prerelease_label}"
fi

echo "${next_version}"
