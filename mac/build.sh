#!/bin/bash
# Build Mimo.app — no Xcode project needed, just swiftc.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Mimo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/"
cp overlay.html settings.html "$APP/Contents/Resources/"
cp AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true

swiftc -O panel_geometry.swift app_menu.swift main.swift product.swift pet_generation.swift -o "$APP/Contents/MacOS/Mimo" \
  -framework Cocoa -framework WebKit -framework Carbon -framework Security

codesign --force -s - "$APP"
echo "built: $PWD/$APP"

# mirror sources for the sandboxed preview server (TCC can't read ~/Desktop)
mkdir -p /private/tmp/ff-serve
rsync -a --delete --exclude build ./ /private/tmp/ff-serve/mac/
