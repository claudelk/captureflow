#!/bin/bash
set -euo pipefail

#==============================================================
# SmartScreenShot — Build, Bundle, Sign, Notarize, DMG
#==============================================================
#
# Usage:
#   ./scripts/build-and-sign.sh
#
# Required environment variables:
#   DEVELOPER_ID   — signing identity, e.g.
#                    "Developer ID Application: John Doe (TEAM123456)"
#
# Required for notarization (skip with SKIP_NOTARIZE=1):
#   APPLE_ID       — Apple ID email
#   TEAM_ID        — 10-char Apple Developer Team ID
#   APP_PASSWORD   — app-specific password from appleid.apple.com
#
# Optional:
#   SKIP_NOTARIZE=1  — skip notarization (for local testing)
#   VERSION          — override version string (default: 1.0.0)
#
#==============================================================

# --- Configuration ---
APP_NAME="SmartScreenShot"
BUNDLE_ID="com.smartscreenshot.app"
VERSION="${VERSION:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${PROJECT_ROOT}/Distribution"
OUTPUT_DIR="${PROJECT_ROOT}/.build/dist"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg"

# --- Validate required env vars ---
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your signing identity (run: security find-identity -v -p codesigning)}"
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    : "${APPLE_ID:?Set APPLE_ID for notarization}"
    : "${TEAM_ID:?Set TEAM_ID for notarization}"
    : "${APP_PASSWORD:?Set APP_PASSWORD for notarization (generate at appleid.apple.com)}"
fi

echo "============================================"
echo "  SmartScreenShot Build Pipeline v${VERSION}"
echo "============================================"
echo ""

# --- Step 1: Build release binary ---
echo "==> [1/7] Building release binary..."
cd "$PROJECT_ROOT"
swift build -c release 2>&1

# Find the release binary (path varies by Swift toolchain)
BINARY=""
for candidate in \
    "${PROJECT_ROOT}/.build/release/${APP_NAME}" \
    "${PROJECT_ROOT}/.build/arm64-apple-macosx/release/${APP_NAME}"; do
    if [ -f "$candidate" ]; then
        BINARY="$candidate"
        break
    fi
done

if [ -z "$BINARY" ]; then
    echo "ERROR: Release binary not found. Check swift build output."
    exit 1
fi

echo "    Binary: $BINARY ($(du -h "$BINARY" | cut -f1))"

# --- Step 2: Create .app bundle ---
echo "==> [2/7] Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "$BINARY" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist and inject version
cp "${DIST_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
    "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" \
    "${APP_BUNDLE}/Contents/Info.plist"

# Copy icon (optional)
ICON_FILE="${DIST_DIR}/AppIcon.icns"
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    echo "    Icon: included"
else
    echo "    Icon: SKIPPED (run Distribution/generate-icon.sh first)"
fi

echo "    Bundle: $APP_BUNDLE"

# --- Step 3: Code sign ---
echo "==> [3/7] Signing .app bundle..."
codesign --deep --force --verify --verbose \
    --sign "$DEVELOPER_ID" \
    --options runtime \
    --entitlements "${DIST_DIR}/SmartScreenShot.entitlements" \
    --timestamp \
    "$APP_BUNDLE"

# --- Step 4: Verify signature ---
echo "==> [4/7] Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo ""
spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true
echo ""

# --- Step 5: Create DMG ---
echo "==> [5/7] Creating DMG..."
rm -f "$DMG_PATH"

DMG_STAGING="${OUTPUT_DIR}/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"

# --- Step 6: Sign DMG ---
echo "==> [6/7] Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
echo "    DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# --- Step 7: Notarize ---
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "==> [7/7] SKIPPED notarization (SKIP_NOTARIZE=1)"
else
    echo "==> [7/7] Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "    Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
fi

# --- Done ---
echo ""
echo "============================================"
echo "  BUILD COMPLETE"
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo "============================================"
