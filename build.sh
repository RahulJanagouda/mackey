#!/bin/bash
# Builds Macky.app and installs it into ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${MACKY_APP_DEST:-$HOME/Applications/Macky.app}"
ICONSET="$(mktemp -d)/AppIcon.iconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

swiftc -O -framework AppKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Macky" \
  "$ROOT"/Sources/*.swift

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Finder and Accessibility show this icon. The menu bar uses the word Macky.
swiftc -framework AppKit -o /tmp/macky-icon "$ROOT/icon.swift"
/tmp/macky-icon /tmp/macky-master.png

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" /tmp/macky-master.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" /tmp/macky-master.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier "com.rahuljanagouda.macky" "$APP"
echo "Installed $APP"
