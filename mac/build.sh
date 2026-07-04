#!/bin/bash
# Build FocusFamiliar.app — no Xcode project needed, just swiftc.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/FocusFamiliar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/"
cp overlay.html "$APP/Contents/Resources/"

swiftc -O main.swift -o "$APP/Contents/MacOS/FocusFamiliar" \
  -framework Cocoa -framework WebKit -framework Carbon

codesign --force -s - "$APP"
echo "built: $PWD/$APP"

# mirror sources for the sandboxed preview server (TCC can't read ~/Desktop)
mkdir -p /private/tmp/ff-serve
rsync -a --delete --exclude build "$(dirname "$0")" /private/tmp/ff-serve/ 2>/dev/null || true
