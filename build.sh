#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="PortTray.app"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/PortTray" "$APP/Contents/MacOS/PortTray"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so it launches locally without Gatekeeper friction.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Done -> $APP"
echo "Launch with:  open $APP"
echo "Install with:  cp -r $APP /Applications/"
