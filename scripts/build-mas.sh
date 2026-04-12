#!/bin/bash
set -euo pipefail

#==============================================================
# CaptureFlow — Mac App Store Build Pipeline
#==============================================================
#
# Usage:
#   ./scripts/build-mas.sh
#
# Required environment variables:
#   MAS_APP_IDENTITY       — "Apple Distribution: Name (TEAMID)"
#   MAS_INSTALLER_IDENTITY — "3rd Party Mac Developer Installer: Name (TEAMID)"
#
# Optional:
#   VERSION — override version string (default: 1.0.0)
#
#==============================================================

# --- Configuration ---
APP_NAME="CaptureFlow"
BUNDLE_ID="com.captureflow.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/.build/dist-mas"
ENTITLEMENTS="$PROJECT_DIR/Distribution/CaptureFlow-MAS.entitlements"
INFO_PLIST="$PROJECT_DIR/Distribution/Info.plist"
ICON="$PROJECT_DIR/Distribution/AppIcon.icns"

# --- Validate ---
: "${MAS_APP_IDENTITY:?Set MAS_APP_IDENTITY to your Apple Distribution identity}"
: "${MAS_INSTALLER_IDENTITY:?Set MAS_INSTALLER_IDENTITY to your 3rd Party Mac Developer Installer identity}"

echo "============================================"
echo "  $APP_NAME MAS Build Pipeline v$VERSION"
echo "============================================"
echo ""

# --- Step 1: Build with MAS flag ---
echo "==> [1/6] Building release binary (MAS)..."
swift build -c release --target "$APP_NAME" -Xswiftc -DMAS 2>&1

# Find the binary
BINARY=""
for candidate in \
    "$PROJECT_DIR/.build/release/$APP_NAME" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"; do
    if [[ -f "$candidate" ]]; then
        BINARY="$candidate"
        break
    fi
done
[[ -n "$BINARY" ]] || { echo "ERROR: binary not found"; exit 1; }
echo "    Binary: $BINARY ($(du -h "$BINARY" | cut -f1))"

# --- Step 2: Assemble .app bundle ---
echo "==> [2/6] Assembling .app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"

cp "$BINARY" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"

# Inject version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
echo "    Version: $VERSION (build $BUILD_NUMBER)"

# Copy icon if it exists
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    echo "    Icon: included"
fi

# Embed provisioning profile (required for TestFlight / App Store)
PROVISION="$PROJECT_DIR/Distribution/CaptureFlow_MAS_Distribution.provisionprofile"
if [[ -f "$PROVISION" ]]; then
    cp "$PROVISION" "$DIST_DIR/$APP_NAME.app/Contents/embedded.provisionprofile"
    echo "    Provisioning profile: embedded"
else
    echo "    WARNING: No provisioning profile found — TestFlight will reject the build"
fi

# Copy resource bundle (localization strings)
RESOURCE_BUNDLE=""
for candidate in \
    "$PROJECT_DIR/.build/release/${APP_NAME}_${APP_NAME}.bundle" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"; do
    if [[ -d "$candidate" ]]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$DIST_DIR/$APP_NAME.app/Contents/Resources/"

    # Fix resource bundle Info.plist — MAS requires CFBundleIdentifier and other keys
    RES_PLIST="$DIST_DIR/$APP_NAME.app/Contents/Resources/$(basename "$RESOURCE_BUNDLE")/Info.plist"
    if [[ -f "$RES_PLIST" ]]; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${BUNDLE_ID}.resources" "$RES_PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}.resources" "$RES_PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME} Resources" "$RES_PLIST" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$RES_PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$RES_PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$RES_PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$RES_PLIST"
        /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string BNDL" "$RES_PLIST" 2>/dev/null || true
        echo "    Resources: included (Info.plist patched)"
    else
        echo "    Resources: included"
    fi
else
    echo "    Resources: SKIPPED (no resource bundle found)"
fi

echo "    Bundle: $DIST_DIR/$APP_NAME.app"

# Strip quarantine xattrs from all files (required for TestFlight/App Store)
xattr -cr "$DIST_DIR/$APP_NAME.app"
echo "    Quarantine xattrs: stripped"

# --- Step 3: Sign all nested bundles individually, then the app ---
echo "==> [3/6] Signing .app bundle (MAS)..."

# Sign the resource bundle first (nested code must be signed before the parent)
RES_BUNDLE_PATH="$DIST_DIR/$APP_NAME.app/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RES_BUNDLE_PATH" ]]; then
    codesign --force \
        --sign "$MAS_APP_IDENTITY" \
        --timestamp \
        "$RES_BUNDLE_PATH"
    echo "    Signed resource bundle"
fi

# Sign the main app (do NOT use --deep; sign components individually)
codesign --force \
    --sign "$MAS_APP_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$DIST_DIR/$APP_NAME.app"

# --- Step 4: Verify signature ---
echo "==> [4/6] Verifying signature..."
codesign --verify --deep --strict "$DIST_DIR/$APP_NAME.app"
echo "    Signature valid"

# --- Step 5: Validate with altool (dry run) ---
echo "==> [5/6] Validating .app bundle..."
# Check all nested code is properly signed
codesign --verify --deep --strict --verbose=2 "$DIST_DIR/$APP_NAME.app" 2>&1 | tail -5
echo "    Validation passed"

# --- Step 6: Create .pkg for App Store ---
echo "==> [6/6] Creating .pkg..."
PKG_PATH="$DIST_DIR/$APP_NAME-$VERSION.pkg"
productbuild \
    --component "$DIST_DIR/$APP_NAME.app" /Applications \
    --sign "$MAS_INSTALLER_IDENTITY" \
    "$PKG_PATH"
echo "    PKG: $PKG_PATH ($(du -h "$PKG_PATH" | cut -f1))"

echo ""
echo "============================================"
echo "  MAS BUILD COMPLETE"
echo "  App:  $DIST_DIR/$APP_NAME.app"
echo "  PKG:  $PKG_PATH"
echo ""
echo "  Upload via Transporter.app or:"
echo "    xcrun altool --upload-app -f \"$PKG_PATH\" \\"
echo "      --type macos --apiKey <KEY> --apiIssuer <ISSUER>"
echo "============================================"
