#!/bin/sh
# Builds DockUnstick.app next to this script (ad-hoc signed).
set -eu
cd "$(dirname "$0")"
APP=DockUnstick.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# Universal binary so the app also runs on Intel Macs.
BIN=$(mktemp -d)
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "$BIN/$arch" Sources/*.swift
done
lipo -create "$BIN/arm64" "$BIN/x86_64" -output "$APP/Contents/MacOS/DockUnstick"
rm -rf "$BIN"

# App icon: render every size iconutil expects from the 1024px master.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signing is convenient for local builds, but macOS ties Accessibility
# permission to its changing code hash. Set CODESIGN_IDENTITY to a stable
# Developer ID identity when repeated authorization after rebuilds is a problem.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier local.dockunstick "$APP"
else
    codesign --force --options runtime --sign "$IDENTITY" --identifier local.dockunstick "$APP"
fi
echo "built $PWD/$APP"
