#!/bin/bash
# Builds Mackey.app and installs it into ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${MACKEY_APP_DEST:-$HOME/Applications/Mackey.app}"
TEMP_DIR="$(mktemp -d)"
ICONSET="$TEMP_DIR/AppIcon.iconset"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
trap 'rm -rf "$TEMP_DIR"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos14.0" -sdk "$SDK" \
    -framework AppKit -framework ServiceManagement \
    -o "$TEMP_DIR/Mackey-$arch" \
    "$ROOT"/Sources/*.swift
done
lipo -create "$TEMP_DIR/Mackey-arm64" "$TEMP_DIR/Mackey-x86_64" \
  -output "$APP/Contents/MacOS/Mackey"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Finder and Accessibility show this icon. The menu bar uses the word Mackey.
swiftc -framework AppKit -o /tmp/mackey-icon "$ROOT/icon.swift"
/tmp/mackey-icon /tmp/mackey-master.png

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" /tmp/mackey-master.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" /tmp/mackey-master.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier "com.rahuljanagouda.mackey" "$APP"
echo "Installed $APP"
