#!/usr/bin/env bash
set -euo pipefail

# This helper packages a browser extension directory into a clean source zip.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER_NAME="${1:-}"

if [[ -z "${BROWSER_NAME}" ]]; then
  echo "Usage: $0 <browser-name> [extension-dir] [output-zip]" >&2
  exit 1
fi

DEFAULT_EXTENSION_DIR="${SCRIPT_DIR}/${BROWSER_NAME}-extension/kotobalibre-openid-callback"
EXTENSION_DIR="${2:-${DEFAULT_EXTENSION_DIR}}"
EXTENSION_NAME="$(basename "${EXTENSION_DIR}")"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/../dist-artifacts/${BROWSER_NAME}-extension"
OUTPUT_ZIP="${3:-${DEFAULT_OUTPUT_DIR}/${EXTENSION_NAME}.zip}"

case "${BROWSER_NAME}" in
  chrome) DISPLAY_NAME="Chrome" ;;
  firefox) DISPLAY_NAME="Firefox" ;;
  *) DISPLAY_NAME="${BROWSER_NAME}" ;;
esac

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

echo "Created ${DISPLAY_NAME} extension zip:"
echo "- ${OUTPUT_ZIP}"
