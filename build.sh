#!/bin/bash
#
# Builds "Dynamic Island.app" into ./build without Xcode.
#
set -euo pipefail
cd "$(dirname "$0")"

APP_DISPLAY_NAME="Dynamic Island"
EXECUTABLE_NAME="DynamicIsland"
BUNDLE_ID="com.wahyubudi.dynamicisland"
VERSION="1.0"
DEPLOYMENT_TARGET="14.0"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --show-sdk-path)"

# ---------------------------------------------------------------------------
# Toolchain workaround
#
# Some Command Line Tools installs ship two module maps that both declare the
# SwiftBridging module (`include/swift/module.modulemap` and
# `include/swift/bridging.modulemap`). Clang then fails with
# "redefinition of module 'SwiftBridging'" on every compile.
#
# Swift resolves that include directory relative to the resource dir, so we
# hand the compiler a shim resource dir whose sibling include/swift directory
# contains only the bridging module map.
# ---------------------------------------------------------------------------
TOOLCHAIN_USR="$(cd "$(dirname "$SWIFTC")/.." && pwd)"
REAL_RESOURCE_DIR="$TOOLCHAIN_USR/lib/swift"
REAL_INCLUDE_DIR="$TOOLCHAIN_USR/include/swift"
SHIM_USR="$(pwd)/.build/toolchain/usr"

rm -rf "$SHIM_USR"
mkdir -p "$SHIM_USR/lib" "$SHIM_USR/include/swift"
ln -sfn "$REAL_RESOURCE_DIR" "$SHIM_USR/lib/swift"
if [ -f "$REAL_INCLUDE_DIR/bridging.modulemap" ]; then
  cp "$REAL_INCLUDE_DIR/bridging" "$SHIM_USR/include/swift/" 2>/dev/null || true
  cp "$REAL_INCLUDE_DIR/bridging.modulemap" "$SHIM_USR/include/swift/"
fi
RESOURCE_DIR="$SHIM_USR/lib/swift"

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SOURCES=$(find Sources -name '*.swift' | sort)

# shellcheck disable=SC2086
"$SWIFTC" \
  -O -whole-module-optimization \
  -target "$(uname -m)-apple-macosx$DEPLOYMENT_TARGET" \
  -sdk "$SDK" \
  -resource-dir "$RESOURCE_DIR" \
  -module-name DynamicIsland \
  $SOURCES \
  -o "$MACOS_DIR/$EXECUTABLE_NAME"

# ---------------------------------------------------------------------------
# Bundle
# ---------------------------------------------------------------------------
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOYMENT_TARGET</string>
    <key>NSLocationUsageDescription</key>
    <string>Dynamic Island uses your location to calculate today's prayer times.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Dynamic Island uses your location to calculate today's prayer times.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" >/dev/null
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built: $APP_DIR"
