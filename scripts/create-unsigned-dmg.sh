#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Kotoba Libre}"
APP_PATH="dist-artifacts/${APP_NAME}.app"
OUT_DIR="dist-artifacts"
DMG_PATH="${OUT_DIR}/${APP_NAME}-unsigned.dmg"
ZIP_PATH="${OUT_DIR}/${APP_NAME}-unsigned-app.zip"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found at ${APP_PATH}. Run './scripts/build-app.sh' first." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

STAGING_DIR="$(mktemp -d "/tmp/${APP_NAME}-dmg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}" "${ZIP_PATH}"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "Created artifacts:"
echo "- ${DMG_PATH}"
echo "- ${ZIP_PATH}"
