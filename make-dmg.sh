#!/bin/bash
#
# Packages the app into a compressed DMG with an Applications shortcut,
# ready for drag-and-drop installation.
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dynamic Island"
APP="build/$APP_NAME.app"
DMG="build/$APP_NAME.dmg"
STAGE="build/dmg"

if [ ! -d "$APP" ]; then
  echo "App bundle not found: $APP (run ./build.sh first)" >&2
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

# ditto preserves bundles, extended attributes and the ad-hoc signature.
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -quiet \
  "$DMG"

rm -rf "$STAGE"

# Verify the image contains a signed app.
MOUNT_POINT="$(mktemp -d /tmp/island-dmg.XXXXXX)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet
trap 'hdiutil detach "$MOUNT_POINT" -quiet || true; rmdir "$MOUNT_POINT" 2>/dev/null || true' EXIT

if [ ! -x "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/DynamicIsland" ]; then
  echo "DMG verification failed: executable missing" >&2
  exit 1
fi
if ! codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME.app" >/dev/null 2>&1; then
  echo "DMG verification failed: invalid app signature" >&2
  exit 1
fi

hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT" 2>/dev/null || true
trap - EXIT

echo "Built: $DMG"
