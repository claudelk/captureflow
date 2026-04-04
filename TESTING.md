# SmartScreenShot — Testing Checklist

---

## Part A: Automated Tests (run by script)

Run: `./scripts/integration-test.sh`

The script uses `screencapture` to create real screenshots and verifies the app
detects and renames them. It toggles settings via `defaults write` and restarts
the app to test different configurations.

**Prerequisites:** SmartScreenShot.app must be running with Accessibility permission.

| # | Test | Status |
|---|------|--------|
| 1.2 | Screenshot is renamed into `screenshot_YYYY-MM-DD/` folder | |
| 1.4 | Renamed file has content-based name (not "Screenshot ...") | |
| 1.5 | File extension is `.png` | |
| 2.3 | While disabled, screenshot is NOT renamed | |
| 2.4 | After re-enabling, screenshots are renamed again | |
| 4.1 | `groupByApp` is off by default | |
| 4.2 | With groupByApp off, folder is `screenshot_YYYY-MM-DD/` | |
| 4.4 | With groupByApp on, folder uses app name (e.g. `screencapture_...`) | |
| 4.5 | After disabling groupByApp, back to `screenshot_` folder | |
| 8.3 | Batch rename 5 files via CLI `sst --rename` | |
| 9.1 | 3 rapid screenshots → all 3 renamed | |
| 9.2 | All renamed files have unique names | |
| 9.3 | All land in the same date folder | |

---

## Part B: Manual Tests (you must do these)

These require GUI interaction (clicking menus, opening dialogs, visual checks).
Mark each as PASS or FAIL. Add notes for any failures.

### Menu Bar — Visual

- [ ] **1.1** Launch app → camera icon appears in menu bar
- [ ] **2.1** Click menu → "Disable" shown when pipeline is running
- [ ] **2.2** Click "Disable" → menu now shows "Enable"
- [ ] **2.5** "Re-analyze Last Screenshot" is grayed out before first rename
- [ ] **2.6** After a rename, "Re-analyze Last Screenshot" is clickable
- [ ] **2.7** Click "Re-analyze Last Screenshot" → file is re-renamed
- [ ] **2.10** "Open Screenshot Folder" → opens folder in Finder
- [ ] **2.11** "Quit SmartScreenShot" → app exits, icon disappears

### Menu Bar — Batch Rename Dialog

- [ ] **2.8** "Batch Rename Screenshots..." → file picker opens, can select multiple PNGs
- [ ] **2.9** Selected files are renamed and moved into `screenshot_YYYY-MM-DD/`
- [ ] **8.1** Cancel file picker without selecting → nothing happens
- [ ] **8.2** Select 1 file → it is renamed
- [ ] **8.4** Batch rename an already-renamed file → re-renamed (no crash)

### Preferences — Screenshot Folder

- [ ] **3.1** "Save screenshots to:" shows current folder path
- [ ] **3.2** Click "Choose..." → folder picker opens
- [ ] **3.3** Select a different folder → path updates
- [ ] **3.4** Take a screenshot → lands in the NEW folder
- [ ] **3.5** Click "Reset" → folder reverts to default
- [ ] **3.6** Take a screenshot → lands in the DEFAULT folder

### Preferences — Group by App (Visual Check)

- [ ] **4.1v** Checkbox "Group screenshots by frontmost app" visible and unchecked by default
- [ ] **4.3** Check the checkbox → no crash, setting persists

### Preferences — Naming Mode

- [ ] **5.1** Dropdown shows "Standard" selected
- [ ] **5.2** "Enhanced" and "Advanced" are visible but disabled (Coming Soon)

### Preferences — Launch at Login

- [ ] **6.1** Checkbox is present
- [ ] **6.2** Toggle on → no crash
- [ ] **6.3** Toggle off → no crash

### Preferences — Global Hotkey (Direct Distribution Only)

- [ ] **7.1** Checkbox "Global hotkey for rename" is present
- [ ] **7.2** Hotkey description shown (e.g., "⌃⌥S")
- [ ] **7.3** Enable → press Ctrl+Option+S → newest screenshot renamed
- [ ] **7.4** Disable → Ctrl+Option+S does nothing

### Preferences — Screenshot with Specific App

- [ ] **1.3** Take screenshot with Cmd+Shift+4 (area select) → renamed correctly

### App Lifecycle

- [ ] **10.1** Quit and relaunch → settings preserved (folder, groupByApp, etc.)
- [ ] **10.2** Preferences window: open, close, reopen → no crash
- [ ] **10.3** App runs stably for 5+ minutes

---

## Test Results Summary

| Section | Automated | Manual Pass | Manual Fail | Manual Not Tested |
|---------|-----------|-------------|-------------|-------------------|
| 1. Basic Pipeline | script | | | |
| 2. Menu Bar Actions | script (enable/disable) | | | |
| 3. Screenshot Folder | — | | | |
| 4. Group by App | script | | | |
| 5. Naming Mode | — | | | |
| 6. Launch at Login | — | | | |
| 7. Global Hotkey | — | | | |
| 8. Batch Rename | script (CLI) | | | |
| 9. Multiple Screenshots | script | | | |
| 10. App Lifecycle | — | | | |

**Tested by:** _______________
**Date:** _______________
**Build:** _______________
**Notes:**
