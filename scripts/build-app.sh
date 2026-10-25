#!/usr/bin/env bash
# Builds a release binary with SwiftPM and wraps it into build/Perch.app
#
#   ./scripts/build-app.sh              for this Mac's processor (fast; what install.sh uses)
#   ./scripts/build-app.sh --universal  Intel + Apple silicon in one app (for sharing a pre-built Perch.app)
set -euo pipefail
cd "$(dirname "$0")/.."

universal=false
for arg in "$@"; do
    case "$arg" in
        --universal) universal=true ;;
        -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

APP="build/Perch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if $universal; then
    # Build each processor type, then merge them into one binary.
    binaries=()
    for arch in x86_64 arm64; do
        swift build -c release --triple "$arch-apple-macosx13.0"
        binaries+=("$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/Perch")
    done
    lipo -create -output "$APP/Contents/MacOS/Perch" "${binaries[@]}"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Perch" "$APP/Contents/MacOS/Perch"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS will launch it locally (extended attributes would make codesign refuse)
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "Built: $APP ($(lipo -archs "$APP/Contents/MacOS/Perch"))"
echo "Run it with:  open \"$APP\""
echo "Install it with:  cp -R \"$APP\" /Applications/"
