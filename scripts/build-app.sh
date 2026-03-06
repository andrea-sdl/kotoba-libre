#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Toro Libre"
BUNDLE_IDENTIFIER="com.andreagrassi.torolibre"
VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
OUT_DIR="dist-artifacts"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: ${VERSION}" >&2
  exit 1
fi

swift build -c release --product ToroLibreApp
BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="${BIN_PATH}/ToroLibreApp"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Built executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/ToroLibreApp"
find "${BIN_PATH}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${RESOURCES_DIR}/" \;

if [[ -f "Sources/ToroLibreCore/Resources/AppIcon.icns" ]]; then
  cp "Sources/ToroLibreCore/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>ToroLibreApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>CFBundleURLName</key>
      <string>${BUNDLE_IDENTIFIER}</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>torolibre</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - --identifier "${BUNDLE_IDENTIFIER}" --timestamp=none "${APP_DIR}"

echo "Built app bundle:"
echo "- ${APP_DIR}"

"$(dirname "$0")/create-unsigned-dmg.sh" "${APP_NAME}"
