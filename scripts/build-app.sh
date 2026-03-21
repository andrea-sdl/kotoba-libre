#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Kotoba Libre"
BUNDLE_IDENTIFIER="com.andreagrassi.kotobalibre"
VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
OUT_DIR="dist-artifacts"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS_PATH="scripts/KotobaLibre.entitlements"
GENERATED_ENTITLEMENTS_PATH="${OUT_DIR}/KotobaLibre.generated.entitlements"
ASSOCIATED_DOMAINS_VALUE="${KOTOBA_ASSOCIATED_DOMAINS:-}"

build_associated_domains_xml() {
  local raw_domain domain normalized_domain
  local -a raw_domains=()

  IFS=',' read -r -a raw_domains <<< "${ASSOCIATED_DOMAINS_VALUE}"
  for raw_domain in "${raw_domains[@]}"; do
    domain="$(printf '%s' "${raw_domain}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${domain}" ]]; then
      continue
    fi

    if [[ "${domain}" == webcredentials:* ]]; then
      normalized_domain="${domain}"
    else
      normalized_domain="webcredentials:${domain}"
    fi

    printf '    <string>%s</string>\n' "${normalized_domain}"
  done
}

write_generated_entitlements() {
  local output_path="$1"
  local associated_domains_xml="$2"

  cat > "${output_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- WebKit media capture on macOS relies on the host app advertising capture capability. -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <!-- Passkeys and security-key WebAuthn in WKWebView only work for associated webcredentials domains. -->
    <key>com.apple.developer.associated-domains</key>
    <array>
${associated_domains_xml}
    </array>
</dict>
</plist>
EOF
}

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: ${VERSION}" >&2
  exit 1
fi

swift build -c release --product KotobaLibreApp
BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="${BIN_PATH}/KotobaLibreApp"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Built executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/KotobaLibreApp"
find "${BIN_PATH}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${RESOURCES_DIR}/" \;

if [[ -f "Sources/KotobaLibreCore/Resources/AppIcon.icns" ]]; then
  cp "Sources/KotobaLibreCore/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
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
  <string>KotobaLibreApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>${APP_NAME} Supported File</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.image</string>
        <string>com.adobe.pdf</string>
        <string>public.plain-text</string>
        <string>public.rtf</string>
        <string>org.openxmlformats.wordprocessingml.document</string>
        <string>public.comma-separated-values-text</string>
      </array>
    </dict>
  </array>
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
        <string>kotobalibre</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>CFBundleURLName</key>
      <string>${BUNDLE_IDENTIFIER}.https</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>https</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>Kotoba Libre requests camera access only when an embedded LibreChat feature needs camera and microphone capture.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Kotoba Libre requests microphone access only so LibreChat's microphone input feature can work.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Kotoba Libre requests speech recognition access only so the voice launcher can transcribe your spoken prompt before sending it to LibreChat.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

SIGNING_ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH}"
if [[ -n "${ASSOCIATED_DOMAINS_VALUE}" ]]; then
  associated_domains_xml="$(build_associated_domains_xml)"
  write_generated_entitlements "${GENERATED_ENTITLEMENTS_PATH}" "${associated_domains_xml}"
  SIGNING_ENTITLEMENTS_PATH="${GENERATED_ENTITLEMENTS_PATH}"
fi

codesign --force --deep --sign - --entitlements "${SIGNING_ENTITLEMENTS_PATH}" --identifier "${BUNDLE_IDENTIFIER}" --timestamp=none "${APP_DIR}"

echo "Built app bundle:"
echo "- ${APP_DIR}"

"$(dirname "$0")/create-unsigned-dmg.sh" "${APP_NAME}"
