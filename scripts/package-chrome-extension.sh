#!/usr/bin/env bash
set -euo pipefail

# This helper creates a clean source zip for the Chrome extension so it can be shared or uploaded.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_EXTENSION_DIR="${SCRIPT_DIR}/chrome-extension/kotobalibre-openid-callback"
EXTENSION_DIR="${1:-${DEFAULT_EXTENSION_DIR}}"
EXTENSION_NAME="$(basename "${EXTENSION_DIR}")"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/../dist-artifacts/chrome-extension"
OUTPUT_ZIP="${2:-${DEFAULT_OUTPUT_DIR}/${EXTENSION_NAME}.zip}"

if [[ ! -d "${EXTENSION_DIR}" ]]; then
  echo "Extension directory not found: ${EXTENSION_DIR}" >&2
  exit 1
fi

if [[ ! -f "${EXTENSION_DIR}/manifest.json" ]]; then
  echo "manifest.json not found in: ${EXTENSION_DIR}" >&2
  exit 1
fi

if [[ ! -f "${EXTENSION_DIR}/icons/icon-16.png" ]]; then
  echo "Extension icon not found: ${EXTENSION_DIR}/icons/icon-16.png" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_ZIP}")"
rm -f "${OUTPUT_ZIP}"

(
  cd "${EXTENSION_DIR}"
  zip -r -X "${OUTPUT_ZIP}" . \
    -x '*.DS_Store' \
    -x '__MACOSX/*' \
    -x '*.pem' \
    -x '*.crx'
)

echo "Created Chrome extension zip:"
echo "- ${OUTPUT_ZIP}"
