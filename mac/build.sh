#!/bin/bash
# Build Mimo.app — no Xcode project needed, just swiftc.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Mimo.app
MODULE_CACHE="${TMPDIR:-/private/tmp}/mimo-swift-module-cache"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MODULE_CACHE"

cp Info.plist "$APP/Contents/"
cp overlay.html settings.html "$APP/Contents/Resources/"
cp AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources/style-reference"
cp assets/style-reference/mimo-style-reference-board.png \
  assets/style-reference/manifest.json "$APP/Contents/Resources/style-reference/"

swiftc -module-cache-path "$MODULE_CACHE" -O panel_geometry.swift app_menu.swift custom_pet.swift character_sheet.swift generation_draft.swift generation_ledger.swift \
  style_reference.swift reference_preprocessor.swift main.swift product.swift pet_generation.swift -o "$APP/Contents/MacOS/Mimo" \
  -framework Cocoa -framework WebKit -framework Carbon -framework Security -framework ImageIO \
  -framework Vision -framework CoreImage -framework CoreVideo

codesign --force -s - "$APP"
echo "built: $PWD/$APP"

# mirror sources for the sandboxed preview server (TCC can't read ~/Desktop)
mkdir -p /private/tmp/ff-serve
rsync -a --delete --exclude build ./ /private/tmp/ff-serve/mac/
