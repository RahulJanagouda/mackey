#!/bin/bash
# Builds Clear Notifications.app and installs it into ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${CLEAR_APP_DEST:-$HOME/Applications/Clear Notifications.app}"
ICONSET="$(mktemp -d)/AppIcon.iconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

swiftc -O -framework AppKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/ClearNotifications" \
  "$ROOT/Sources/main.swift"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Menu-bar template icon, also used so the app is recognizable in Accessibility.
swiftc -framework AppKit -o /tmp/clear-notifications-icon "$ROOT/icon.swift"
/tmp/clear-notifications-icon /tmp/clear-notifications-master.png

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" /tmp/clear-notifications-master.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" /tmp/clear-notifications-master.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier "com.rahuljanagouda.clearnotifications" "$APP"
echo "Installed $APP"
