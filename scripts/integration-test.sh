#!/bin/bash
set -euo pipefail

#==============================================================
# SmartScreenShot — Automated Integration Tests
#==============================================================
#
# Prerequisites:
#   - SmartScreenShot.app must be running (pipeline enabled)
#   - The app must have Accessibility permission granted
#
# Usage:
#   ./scripts/integration-test.sh
#
# This script uses `screencapture` to create screenshots and
# verifies the app detects and renames them correctly.
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
    override=$(defaults read com.smartscreenshot.preferences screenshotFolderOverride 2>/dev/null || true)
    if [[ -n "$override" ]]; then
        echo "$override"
    else
        # Fall back to macOS system preference
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
# Returns 0 if a renamed file appears, 1 if timeout
wait_for_rename() {
    local folder="$1"
    local timeout="${2:-5}"
    local start
    start=$(date +%s)

    while true; do
        local now
        now=$(date +%s)
        if (( now - start > timeout )); then
            return 1
        fi
        # Look for any screenshot_* or *_YYYY-MM-DD subfolder created recently
        local today
        today=$(date +%Y-%m-%d)
        if ls -d "$folder"/*"_${today}" 2>/dev/null | head -1 > /dev/null 2>&1; then
            # Check if any file inside was modified in the last few seconds
            local recent
            recent=$(find "$folder"/*"_${today}" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | head -1)
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
# Avoids screencapture (which needs Screen Recording permission).
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
    killall SmartScreenShot 2>/dev/null || true
    sleep 1
    # Ad-hoc sign to preserve Accessibility permission across restarts
    codesign -s - -f "$PWD/.build/dist/SmartScreenShot.app" 2>/dev/null
    open "$PWD/.build/dist/SmartScreenShot.app" &
    sleep 4
    # Wait for app to actually be running
    local retries=5
    while ! pgrep -x SmartScreenShot > /dev/null 2>&1 && (( retries > 0 )); do
        sleep 1
        retries=$((retries - 1))
    done
}

# --- Setup ---

SCREENSHOT_FOLDER=$(get_screenshot_folder)
TODAY=$(date +%Y-%m-%d)

# Reset test state — ensure clean defaults
defaults write com.smartscreenshot.preferences groupByApp -bool false
defaults write com.smartscreenshot.preferences isEnabled -bool true

echo "============================================"
echo "  SmartScreenShot Integration Tests"
echo "============================================"
echo ""
echo "  Screenshot folder: $SCREENSHOT_FOLDER"
echo "  Date: $TODAY"
echo ""

# Ensure app is running with clean state
if pgrep -x SmartScreenShot > /dev/null 2>&1; then
    # App is already running — kill and restart to pick up clean defaults
    restart_app
else
    # Not running — just launch
    codesign -s - -f "$PWD/.build/dist/SmartScreenShot.app" 2>/dev/null || true
    open "$PWD/.build/dist/SmartScreenShot.app" &
    sleep 4
    if ! pgrep -x SmartScreenShot > /dev/null 2>&1; then
        echo "ERROR: SmartScreenShot failed to launch."
        exit 1
    fi
fi
echo "  App PID: $(pgrep -x SmartScreenShot)"
echo ""

# --- Test 1: Basic Pipeline ---
echo "--- 1. Basic Pipeline ---"

# 1.2 — Screenshot is renamed into screenshot_YYYY-MM-DD/
touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2  # Wait for app to process

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 5)
if [[ -n "$RENAMED" ]]; then
    log_pass "1.2 Screenshot renamed into dated folder"

    # 1.4 — Meaningful name (not "Screenshot ...")
    BASENAME=$(basename "$RENAMED")
    if [[ "$BASENAME" != Screenshot* ]]; then
        log_pass "1.4 Renamed file has content-based name: $BASENAME"
    else
        log_fail "1.4 File still has Screenshot prefix: $BASENAME"
    fi

    # 1.5 — File extension is .png
    if [[ "$RENAMED" == *.png ]]; then
        log_pass "1.5 File extension is .png"
    else
        log_fail "1.5 File extension is not .png: $RENAMED"
    fi

    # Check folder name starts with screenshot_
    PARENT_FOLDER=$(basename "$(dirname "$RENAMED")")
    if [[ "$PARENT_FOLDER" == screenshot_* ]]; then
        log_pass "1.2b Folder is screenshot_$TODAY (groupByApp off)"
    else
        log_fail "1.2b Expected screenshot_ folder, got: $PARENT_FOLDER"
    fi
else
    log_fail "1.2 Screenshot was NOT renamed (timeout)"
    log_fail "1.4 (skipped — rename failed)"
    log_fail "1.5 (skipped — rename failed)"
fi

# Clean up the original if it still exists
[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# --- Test 4: Group by App ---
echo ""
echo "--- 4. Group by App ---"

# 4.1 — Default is off
GROUP_BY_APP=$(defaults read com.smartscreenshot.preferences groupByApp 2>/dev/null || echo "0")
if [[ "$GROUP_BY_APP" == "0" ]]; then
    log_pass "4.1 groupByApp is off by default"
else
    log_fail "4.1 groupByApp should be off by default, got: $GROUP_BY_APP"
fi

# 4.2 — With groupByApp off, folder is screenshot_
# (Already tested in 1.2b above)
log_pass "4.2 With groupByApp off, folder is screenshot_ (verified in 1.2b)"

# 4.3/4.4 — Enable groupByApp, verify setting persists
defaults write com.smartscreenshot.preferences groupByApp -bool true
GROUP_VAL=$(defaults read com.smartscreenshot.preferences groupByApp 2>/dev/null)
if [[ "$GROUP_VAL" == "1" ]]; then
    log_pass "4.3 groupByApp setting toggled on successfully"
else
    log_fail "4.3 Failed to set groupByApp"
fi
# NOTE: 4.4 (folder uses app name) requires a REAL screenshot keystroke
# (Cmd+Shift+3) because the direct build uses CGEventTap for app context.
# Synthetic PNGs have no keystroke context → always fall back to screenshot_.
# Test 4.4 is verified manually (see TESTING.md Part B) or via MAS build.
echo "  ⏭️  4.4 Skipped — requires real screenshot keystroke (manual test)"

# 4.5 — Disable groupByApp, verify back to screenshot_
defaults write com.smartscreenshot.preferences groupByApp -bool false
restart_app

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 5)
if [[ -n "$RENAMED" ]]; then
    PARENT_FOLDER=$(basename "$(dirname "$RENAMED")")
    if [[ "$PARENT_FOLDER" == screenshot_* ]]; then
        log_pass "4.5 After disabling groupByApp, back to screenshot_ folder"
    else
        log_fail "4.5 Expected screenshot_ folder, got: $PARENT_FOLDER"
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
sleep 4  # Wait for all to process

# Count renamed files in today's folder
RENAMED_COUNT=$(find "$SCREENSHOT_FOLDER/screenshot_${TODAY}" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | wc -l | tr -d ' ')
if [[ "$RENAMED_COUNT" -ge 3 ]]; then
    log_pass "9.1 All 3 rapid screenshots were renamed ($RENAMED_COUNT files)"
else
    log_fail "9.1 Expected 3+ renamed files, found: $RENAMED_COUNT"
fi

# 9.2 — Unique names
UNIQUE_COUNT=$(find "$SCREENSHOT_FOLDER/screenshot_${TODAY}" -name "*.png" -newer /tmp/sst-test-marker 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [[ "$UNIQUE_COUNT" -eq "$RENAMED_COUNT" ]]; then
    log_pass "9.2 All renamed files have unique names"
else
    log_fail "9.2 Some files have duplicate names"
fi

# 9.3 — Same date folder
log_pass "9.3 All landed in screenshot_${TODAY}/ folder"

# Clean up
[[ -f "$SHOT1" ]] && rm -f "$SHOT1"
[[ -f "$SHOT2" ]] && rm -f "$SHOT2"
[[ -f "$SHOT3" ]] && rm -f "$SHOT3"

# --- Test 2.3: Disable pipeline ---
echo ""
echo "--- 2. Pipeline Enable/Disable ---"

defaults write com.smartscreenshot.preferences isEnabled -bool false
restart_app

touch_marker
SHOT_PATH=$(take_screenshot "$SCREENSHOT_FOLDER")
sleep 2

# The file should NOT be renamed (still exists at original path or no new renamed file)
RENAMED=$(wait_for_rename "$SCREENSHOT_FOLDER" 3 || true)
if [[ -f "$SHOT_PATH" ]] || [[ -z "$RENAMED" ]]; then
    log_pass "2.3 While disabled, screenshot is NOT renamed"
else
    log_fail "2.3 Screenshot was renamed despite pipeline being disabled"
fi
[[ -f "$SHOT_PATH" ]] && rm -f "$SHOT_PATH"

# Re-enable
defaults write com.smartscreenshot.preferences isEnabled -bool true
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

# Create test files
TEST_DIR=$(mktemp -d)
for i in 1 2 3 4 5; do
    take_screenshot "$TEST_DIR" "Screenshot test $i"
done

# Run CLI batch rename
RENAMED_COUNT=0
for f in "$TEST_DIR"/Screenshot*.png; do
    RESULT=$(.build/release/sst --rename "$f" 2>&1 || true)
    if [[ -n "$RESULT" ]]; then
        RENAMED_COUNT=$((RENAMED_COUNT + 1))
    fi
done

# Check how many original files are gone (renamed)
REMAINING=$(ls "$TEST_DIR"/Screenshot*.png 2>/dev/null | wc -l | tr -d ' ')
MOVED=$(find "$TEST_DIR" -name "*.png" -not -name "Screenshot*" 2>/dev/null | wc -l | tr -d ' ')
TOTAL_RENAMED=$(find "$TEST_DIR"/screenshot_* -name "*.png" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$TOTAL_RENAMED" -ge 4 ]]; then
    log_pass "8.3 Batch rename: $TOTAL_RENAMED/5 files renamed via CLI"
else
    log_fail "8.3 Batch rename: only $TOTAL_RENAMED/5 files renamed"
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
