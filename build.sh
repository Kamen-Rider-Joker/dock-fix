#!/bin/sh
# Builds DockUnstick.app next to this script (ad-hoc signed).
set -eu
cd "$(dirname "$0")"
APP=DockUnstick.app
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -o "$APP/Contents/MacOS/DockUnstick" Sources/main.swift
codesign --force --sign - --identifier local.dockunstick "$APP"
echo "built $PWD/$APP"
