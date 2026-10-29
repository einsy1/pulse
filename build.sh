#!/bin/bash
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$ROOT/Pulse.app"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pulse-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [ -d "$DEVELOPER_ROOT/Toolchains/XcodeDefault.xctoolchain" ]; then
  TOOL_BIN="$DEVELOPER_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin"
  SDK="$DEVELOPER_ROOT/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
else
  TOOL_BIN="$DEVELOPER_ROOT/usr/bin"
  SDK="$DEVELOPER_ROOT/SDKs/MacOSX.sdk"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
SOURCES=("$ROOT/Sources/Pulse/main.swift" "$ROOT/Sources/Pulse/HardwareMetrics.swift" "$ROOT/Sources/Pulse/Preferences.swift")
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement)
"$TOOL_BIN/swiftc" -sdk "$SDK" -parse-as-library -O -target arm64-apple-macosx14.0 \
  "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "$BUILD_DIR/Pulse-arm64"
"$TOOL_BIN/swiftc" -sdk "$SDK" -parse-as-library -O -target x86_64-apple-macosx14.0 \
  "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "$BUILD_DIR/Pulse-x86_64"
"$TOOL_BIN/lipo" -create "$BUILD_DIR/Pulse-arm64" "$BUILD_DIR/Pulse-x86_64" \
  -output "$APP/Contents/MacOS/Pulse"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built universal app: %s\n' "$APP"
