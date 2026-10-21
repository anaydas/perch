#!/usr/bin/env bash
# Builds a release binary with SwiftPM and wraps it into build/Perch.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Perch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Perch" "$APP/Contents/MacOS/Perch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS will launch it locally
codesign --force --deep --sign - "$APP"

echo "Built: $APP"
echo "Run it with:  open \"$APP\""
echo "Install it with:  cp -R \"$APP\" /Applications/"
