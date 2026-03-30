#!/bin/bash
set -euo pipefail

# Generate AppIcon.icns for SmartScreenShot
#
# Prerequisites: place a 1024x1024 PNG at Distribution/AppIcon-1024.png
# You can export camera.viewfinder from SF Symbols.app at 1024x1024,
# or use any custom icon design.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/AppIcon-1024.png"
ICONSET="${SCRIPT_DIR}/AppIcon.iconset"
OUTPUT="${SCRIPT_DIR}/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "ERROR: Place a 1024x1024 PNG at: $SOURCE"
    echo "Tip: Open SF Symbols.app -> search camera.viewfinder -> File -> Export"
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Required sizes for macOS .icns
for size in 16 32 64 128 256 512 1024; do
    case $size in
        16)   sips -z 16 16 "$SOURCE" --out "${ICONSET}/icon_16x16.png" >/dev/null ;;
        32)   sips -z 32 32 "$SOURCE" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
              sips -z 32 32 "$SOURCE" --out "${ICONSET}/icon_32x32.png" >/dev/null ;;
        64)   sips -z 64 64 "$SOURCE" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null ;;
        128)  sips -z 128 128 "$SOURCE" --out "${ICONSET}/icon_128x128.png" >/dev/null ;;
        256)  sips -z 256 256 "$SOURCE" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
              sips -z 256 256 "$SOURCE" --out "${ICONSET}/icon_256x256.png" >/dev/null ;;
        512)  sips -z 512 512 "$SOURCE" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null
              sips -z 512 512 "$SOURCE" --out "${ICONSET}/icon_512x512.png" >/dev/null ;;
        1024) sips -z 1024 1024 "$SOURCE" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null ;;
    esac
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "Created: $OUTPUT"
