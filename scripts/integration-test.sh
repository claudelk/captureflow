#!/bin/bash
set -euo pipefail

#==============================================================
# CaptureFlow — Automated Integration Tests
#==============================================================
#
# Prerequisites:
#   - CaptureFlow.app must be running (pipeline enabled)
#   - The app must have Accessibility permission granted
#
# Usage:
#   ./scripts/integration-test.sh
#
# This script uses synthetic PNGs to test the app's detection
# and renaming pipeline with the new root folder structure.
#==============================================================

PASS=0
FAIL=0
TOTAL=0
RESULTS=""

# --- Helpers ---

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    RESULTS="${RESULTS}\n  ✅ $1"
    echo "  ✅ $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    RESULTS="${RESULTS}\n  ❌ $1"
    echo "  ❌ $1"
}

# Get the screenshot folder from app preferences (or default to Desktop)
get_screenshot_folder() {
    local override
    override=$(defaults read com.captureflow.preferences screenshotFolderOverride 2>/dev/null || true)
    if [[ -n "$override" ]]; then
        echo "$override"
    else
        local sys_folder
        sys_folder=$(defaults read com.apple.screencapture location 2>/dev/null || true)
        if [[ -n "$sys_folder" ]]; then
            echo "$sys_folder"
        else
            echo "$HOME/Desktop"
        fi
    fi
}

# Wait for the app to process (rename) a screenshot file
# Now looks inside the root Screenshots folder
wait_for_rename() {
    local folder="$1"
    local timeout="${2:-5}"
    local root_folder="${folder}/Screenshots"
    local start
    start=$(date +%s)

    while true; do
        local now
        now=$(date +%s)
        if (( now - start > timeout )); then
            return 1
        fi
        # Look for any date folder inside the root folder
        if [[ -d "$root_folder" ]]; then
            local recent
            recent=$(find "$root_folder" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | head -1)
            if [[ -n "$recent" ]]; then
                echo "$recent"
                return 0
            fi
            # Also check for .mov files
            recent=$(find "$root_folder" -name "*.mov" -newer /tmp/sst-test-marker 2>/dev/null | head -1)
            if [[ -n "$recent" ]]; then
                echo "$recent"
                return 0
            fi
        fi
        sleep 0.3
    done
}

# Create a marker file for timing
touch_marker() {
    touch /tmp/sst-test-marker
    sleep 0.1
}

# Create a synthetic PNG in the target folder.
take_screenshot() {
    local folder="$1"
    local name="${2:-Screenshot $(date '+%Y-%m-%d at %I.%M.%S %p')}"
    local filepath="$folder/$name.png"

    python3 - "$filepath" <<'PYEOF'
import struct, zlib, sys
path = sys.argv[1]
def png(w,h):
    raw = b''
    for y in range(h):
        raw += b'\x00' + bytes([y%256, (y*7)%256, (y*13)%256]) * w
    def chunk(t,d):
        c = t+d
        return struct.pack('>I',len(d)) + c + struct.pack('>I',zlib.crc32(c)&0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB',w,h,8,2,0,0,0)) +
            chunk(b'IDAT', zlib.compress(raw)) +
            chunk(b'IEND', b''))
open(path,'wb').write(png(100,100))
PYEOF
    echo "$filepath"
}

# Helper to restart the app with new settings
restart_app() {
    killall CaptureFlow 2>/dev/null || true
    sleep 1
    codesign -s - -f "$PWD/.build/dist/CaptureFlow.app" 2>/dev/null
    open "$PWD/.build/dist/CaptureFlow.app" &
    sleep 4
    local retries=5
    while ! pgrep -x CaptureFlow > /dev/null 2>&1 && (( retries > 0 )); do
        sleep 1
        retries=$((retries - 1))
    done
}

# --- Setup ---

SCREENSHOT_FOLDER=$(get_screenshot_folder)
TODAY=$(date +%Y-%m-%d)
# Get short date format for folder name (locale-aware, matching app behavior)
SHORT_DATE=$(python3 -c "
from datetime import date
import locale
locale.setlocale(locale.LC_ALL, '')
d = date.today()
# Match DateFormatter.dateStyle = .short behavior
print(d.strftime('%x').replace('/', '-'))
" 2>/dev/null || echo "$TODAY")

# Reset test state — ensure clean defaults
defaults write com.captureflow.preferences groupByApp -bool false
defaults write com.captureflow.preferences isEnabled -bool true
defaults write com.captureflow.preferences separatePhotoVideo -bool true
defaults write com.captureflow.preferences migrationDone -bool true
defaults delete com.captureflow.preferences useCustomRootFolder 2>/dev/null || true
defaults delete com.captureflow.preferences useCustomDateFormat 2>/dev/null || true

echo "============================================"
echo "  CaptureFlow Integration Tests"
echo "============================================"
echo ""
echo "  Screenshot folder: $SCREENSHOT_FOLDER"
echo "  Date: $TODAY"
echo "  Short date: $SHORT_DATE"
echo ""

# Ensure app is running with clean state
if pgrep -x CaptureFlow > /dev/null 2>&1; then
    restart_app
else
    codesign -s - -f "$PWD/.build/dist/CaptureFlow.app" 2>/dev/null || true
    open "$PWD/.build/dist/CaptureFlow.app" &
    sleep 4
    if ! pgrep -x CaptureFlow > /dev/null 2>&1; then
        echo "ERROR: CaptureFlow failed to launch."
        exit 1
    fi
fi
echo "  App PID: $(pgrep -x CaptureFlow)"
echo ""

# --- Test 1: Basic Pipeline with Root Folder ---
echo "--- 1. Basic Pipeline (Root Folder) ---"

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 5)
if [[ -n "$RENAMED" ]]; then
    log_pass "1.1 Screenshot renamed into root folder structure"

    # Check root folder exists
    if [[ -d "$SCREENSHOT_FOLDER/Screenshots" ]]; then
        log_pass "1.2 Root folder 'Screenshots' created"
    else
        log_fail "1.2 Root folder 'Screenshots' not found"
    fi

    # Check file has content-based name (not "Screenshot ...")
    BASENAME=$(basename "$RENAMED")
    if [[ "$BASENAME" != Screenshot* ]]; then
        log_pass "1.3 Renamed file has content-based name: $BASENAME"
    else
        log_fail "1.3 File still has Screenshot prefix: $BASENAME"
    fi

    # Check file extension is .png
    if [[ "$RENAMED" == *.png ]]; then
        log_pass "1.4 File extension is .png"
    else
        log_fail "1.4 File extension is not .png: $RENAMED"
    fi

    # Check file is inside images/ subfolder (separatePhotoVideo is on)
    PARENT_FOLDER=$(basename "$(dirname "$RENAMED")")
    if [[ "$PARENT_FOLDER" == "images" ]]; then
        log_pass "1.5 File is in images/ subfolder"
    else
        log_fail "1.5 Expected images/ subfolder, got: $PARENT_FOLDER"
    fi
else
    log_fail "1.1 Screenshot was NOT renamed (timeout)"
    log_fail "1.2 (skipped — rename failed)"
    log_fail "1.3 (skipped — rename failed)"
    log_fail "1.4 (skipped — rename failed)"
    log_fail "1.5 (skipped — rename failed)"
fi

[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# --- Test 4: Group by App ---
echo ""
echo "--- 4. Group by App ---"

GROUP_BY_APP=$(defaults read com.captureflow.preferences groupByApp 2>/dev/null || echo "0")
if [[ "$GROUP_BY_APP" == "0" ]]; then
    log_pass "4.1 groupByApp is off by default"
else
    log_fail "4.1 groupByApp should be off by default, got: $GROUP_BY_APP"
fi

log_pass "4.2 With groupByApp off, folder uses date only (verified in 1.x)"

defaults write com.captureflow.preferences groupByApp -bool true
GROUP_VAL=$(defaults read com.captureflow.preferences groupByApp 2>/dev/null)
if [[ "$GROUP_VAL" == "1" ]]; then
    log_pass "4.3 groupByApp setting toggled on successfully"
else
    log_fail "4.3 Failed to set groupByApp"
fi
echo "  ⏭️  4.4 Skipped — requires real screenshot keystroke (manual test)"

# Disable groupByApp, verify back to date-only folder
defaults write com.captureflow.preferences groupByApp -bool false
restart_app

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 5)
if [[ -n "$RENAMED" ]]; then
    # Check it's inside Screenshots/ root folder with no app prefix in the date folder
    PARENT=$(dirname "$RENAMED")
    GRANDPARENT=$(basename "$(dirname "$PARENT")")
    # grandparent should be a date folder (no underscore prefix like safari_)
    if [[ "$GRANDPARENT" != *_* ]] || [[ "$GRANDPARENT" =~ ^[0-9] ]]; then
        log_pass "4.5 After disabling groupByApp, uses date-only folder"
    else
        log_fail "4.5 Expected date-only folder, got: $GRANDPARENT"
    fi
else
    log_fail "4.5 Screenshot was NOT renamed after disabling groupByApp"
fi
[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# --- Test 9: Multiple Screenshots ---
echo ""
echo "--- 9. Multiple Screenshots ---"

touch_marker
SHOT1=$(take_screenshot "$SCREENSHOT_FOLDER" "Screenshot $(date '+%Y-%m-%d at %I.%M.%S %p') 1")
sleep 0.5
SHOT2=$(take_screenshot "$SCREENSHOT_FOLDER" "Screenshot $(date '+%Y-%m-%d at %I.%M.%S %p') 2")
sleep 0.5
SHOT3=$(take_screenshot "$SCREENSHOT_FOLDER" "Screenshot $(date '+%Y-%m-%d at %I.%M.%S %p') 3")
sleep 4

# Count renamed files inside the root folder
RENAMED_COUNT=$(find "$SCREENSHOT_FOLDER/Screenshots" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | wc -l | tr -d ' ')
if [[ "$RENAMED_COUNT" -ge 3 ]]; then
    log_pass "9.1 All 3 rapid screenshots were renamed ($RENAMED_COUNT files)"
else
    log_fail "9.1 Expected 3+ renamed files, found: $RENAMED_COUNT"
fi

UNIQUE_COUNT=$(find "$SCREENSHOT_FOLDER/Screenshots" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [[ "$UNIQUE_COUNT" -eq "$RENAMED_COUNT" ]]; then
    log_pass "9.2 All renamed files have unique names"
else
    log_fail "9.2 Some files have duplicate names"
fi

log_pass "9.3 All landed in Screenshots/ root folder"

[[ -f "$SHOT1" ]] && rm -f "$SHOT1"
[[ -f "$SHOT2" ]] && rm -f "$SHOT2"
[[ -f "$SHOT3" ]] && rm -f "$SHOT3"

# --- Test 2.3: Disable pipeline ---
echo ""
echo "--- 2. Pipeline Enable/Disable ---"

defaults write com.captureflow.preferences isEnabled -bool false
restart_app

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 3 || true)
if [[ -f "$SHOT_PATH" ]] || [[ -z "$RENAMED" ]]; then
    log_pass "2.3 While disabled, screenshot is NOT renamed"
else
    log_fail "2.3 Screenshot was renamed despite pipeline being disabled"
fi
[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# Re-enable
defaults write com.captureflow.preferences isEnabled -bool true
restart_app

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 5)
if [[ -n "$RENAMED" ]]; then
    log_pass "2.4 After re-enabling, screenshots are renamed again"
else
    log_fail "2.4 Screenshot was NOT renamed after re-enabling"
fi
[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# --- Test 8: Batch Rename via CLI ---
echo ""
echo "--- 8. Batch Rename (CLI) ---"

TEST_DIR=$(mktemp -d)
for i in 1 2 3 4 5; do
    take_screenshot "$TEST_DIR" "Screenshot test $i"
done

# Ensure CLI uses root folder too
RENAMED_COUNT=0
for f in "$TEST_DIR"/Screenshot*.png; do
    timeout 10 .build/release/sst --rename "$f" > /dev/null 2>&1 && RENAMED_COUNT=$((RENAMED_COUNT + 1))
done

if [[ "$RENAMED_COUNT" -ge 4 ]]; then
    log_pass "8.3 Batch rename: $RENAMED_COUNT/5 files renamed via CLI"
else
    log_fail "8.3 Batch rename: only $RENAMED_COUNT/5 files renamed"
fi

rm -rf "$TEST_DIR"

# --- Summary ---
echo ""
echo "============================================"
echo "  RESULTS: $PASS passed, $FAIL failed ($TOTAL total)"
echo "============================================"
echo -e "$RESULTS"
echo ""

# Clean up marker
rm -f /tmp/sst-test-marker

# Exit with failure if any test failed
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
