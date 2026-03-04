#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Create, sign, notarize, and staple a DMG for a macOS app bundle.

Required environment variables:
  DEVELOPER_ID_APP_CERT   Developer ID Application certificate common name
  NOTARY_PROFILE          Keychain profile name created via:
                          xcrun notarytool store-credentials <name> ...

Optional environment variables:
  APP_PATH                Path to .app bundle (default: ./CodeRabbit.app)
  PRODUCT_NAME            Product name used in file names (default: CodeRabbit)
  VERSION                 Version string for output file name (default: from app Info.plist)
  OUTPUT_DIR              Output directory (default: ./dist)
  BACKGROUND_IMAGE        Absolute path to .png background image for DMG window
  SKIP_APP_VERIFY         Set to 1 to skip preflight app signature verification

Examples:
  DEVELOPER_ID_APP_CERT="Developer ID Application: Example Corp (ABCDE12345)" \
  NOTARY_PROFILE="AC_NOTARY" \
  ./scripts/create_signed_notarized_dmg.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${DEVELOPER_ID_APP_CERT:?Set DEVELOPER_ID_APP_CERT to your Developer ID Application certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name}"

APP_PATH="${APP_PATH:-./CodeRabbit.app}"
PRODUCT_NAME="${PRODUCT_NAME:-CodeRabbit}"
OUTPUT_DIR="${OUTPUT_DIR:-./dist}"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
fi
VERSION="${VERSION:-0.0.0}"

mkdir -p "$OUTPUT_DIR"

RW_DMG="$OUTPUT_DIR/${PRODUCT_NAME}-${VERSION}-rw.dmg"
FINAL_DMG="$OUTPUT_DIR/${PRODUCT_NAME}-${VERSION}.dmg"
VOLUME_NAME="${PRODUCT_NAME} ${VERSION}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${PRODUCT_NAME}.dmg.XXXXXX")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "==> Preflight checks"
if [[ "${SKIP_APP_VERIFY:-0}" != "1" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl -a -vv -t exec "$APP_PATH"
else
  echo "Skipping app signature verification (SKIP_APP_VERIFY=1)"
fi

echo "==> Building DMG"
rm -f "$RW_DMG" "$FINAL_DMG"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -n "$BACKGROUND_IMAGE" ]]; then
  if [[ ! -f "$BACKGROUND_IMAGE" ]]; then
    echo "Background image not found: $BACKGROUND_IMAGE" >&2
    exit 1
  fi
  mkdir -p "$STAGING_DIR/.background"
  cp "$BACKGROUND_IMAGE" "$STAGING_DIR/.background/background.png"
fi

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG"

if [[ -n "$BACKGROUND_IMAGE" ]]; then
  echo "==> Applying Finder layout + background"
  MOUNT_POINT="/Volumes/$VOLUME_NAME"
  hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
  APP_BASENAME="$(basename "$APP_PATH")"

  osascript <<OSA
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 840, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_BASENAME" of container window to {180, 250}
    set position of item "Applications" of container window to {540, 250}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
OSA

  # Persist Finder metadata before conversion.
  sync
  hdiutil detach "$MOUNT_POINT" -quiet
  MOUNT_POINT=""
fi

hdiutil convert "$RW_DMG" -format UDZO -o "$FINAL_DMG"

echo "==> Signing DMG"
codesign --force --sign "$DEVELOPER_ID_APP_CERT" --timestamp --verbose "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple -v "$FINAL_DMG"
xcrun stapler validate -v "$FINAL_DMG"

echo "==> Gatekeeper assessment"
spctl -a -vv -t open "$FINAL_DMG"

echo "Done: $FINAL_DMG"
