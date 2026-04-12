# CaptureFlow — Implementation Progress

---

## Step 1 — CLI naming brain ✅ (2026-03-29)

**Goal:** standalone `sst` binary that takes an image path and prints a filename slug.

### Implemented
- `CaptureFlowCore` SPM library target
  - `ImageNamer` protocol + `CaptureContext` struct
  - `SlugGenerator` — kebab-case slug generation + OCR line scoring
  - `VisionOnlyNamer` — Tier 1 namer (OCR + scene classification)
- `sst` executable target
  - Accepts `<image-path>` + optional `--verbose` / `-v` flag
  - Verbose mode prints OCR lines with confidence + score, classification labels, then slug
  - Plain mode prints slug only (pipe-friendly)

### Design decisions
- `@main` struct entry point (not `main.swift`) for clean async support
- `withCheckedThrowingContinuation` wraps Vision completion-handler API
- OCR: `accurate` mode, system languages + `en-US` fallback
- Slug scoring penalises all-caps, short strings, low letter ratio
- Classification fallback filters `others_*` catch-all labels
- Ultimate fallback: `"untitled"`

### Test it
```bash
swift build
.build/debug/sst /path/to/screenshot.png
.build/debug/sst /path/to/screenshot.png --verbose
```

---

## Step 2 — Context capture + FSEvents daemon ✅ (2026-03-29)

**Goal:** background daemon that captures app context at keystroke time and auto-renames screenshots.

### Implemented
- `CaptureContextStore` — lock-based (`NSLock`) ring buffer, nearest-match lookup within 10 s window
- `ScreenshotPreferences` — reads `com.apple.screencapture location`, falls back to `~/Desktop`
- `KeystrokeTap` — passive CGEventTap for Cmd+Shift+3/4/5; captures `NSWorkspace.frontmostApplication` **synchronously** on keystroke
- `ScreenshotWatcher` — FSEvents with `kFSEventStreamCreateFlagFileEvents`; filters for `created|renamed` events, skips hidden temp files, direct-children-only filter prevents reprocessing renamed files; passes `detectedAt` timestamp from callback
- `RenameEngine` actor — 0.5 s write-settle delay, context matching via `detectedAt`, slug generation, collision-safe move
- `ssd` daemon binary — wires everything together, prompts for Accessibility on first run

### Design decisions
- `CaptureContextStore` uses `NSLock` (not an actor) so `KeystrokeTap` can `store()` synchronously from the CGEventTap C callback — eliminates the race where an async store hadn't completed before `nearest()` was called
- `KeystrokeTap` uses `.listenOnly` passive tap — no event modification, minimal permission surface
- `ScreenshotWatcher` captures `Date()` inside the FSEvents callback and passes it as `detectedAt` — much closer to the actual keystroke than `Date()` inside the async Task
- `RenameEngine.recentlyProcessed` dictionary (3 s TTL) prevents double-processing when FSEvents fires both `created` and `renamed` for the same file
- Context match window is 10 seconds — accounts for ~5 s delay between keystroke and FSEvents detection
- Date formatting uses `Calendar.dateComponents` — thread-safe, no `DateFormatter` shared state
- Browser URL capture stubbed as `nil` — planned for Step 3 (toggle in Preferences)

### Test it
```bash
swift build
.build/debug/ssd
# Take a screenshot — watch the terminal output
```

---

## Step 3 — Menu bar app ✅ (2026-03-29)

**Goal:** proper macOS menu bar app replacing the CLI daemon with GUI controls.

### Implemented
- `CaptureFlow` SPM executable target (`Sources/App/`)
- `AppEntry.swift` — `@main` with `NSApplication.setActivationPolicy(.accessory)` (no Dock icon), Accessibility check via NSAlert
- `PipelineController.swift` — wraps KeystrokeTap + ScreenshotWatcher + RenameEngine with `start()`/`stop()` lifecycle; tracks last processed file for re-analyze
- `StatusBarController.swift` — NSStatusItem with SF Symbol `camera.viewfinder`, NSMenu with Enable/Disable, Re-analyze Last, Open Folder, Preferences, Quit
- `PreferencesStore.swift` — UserDefaults wrapper (`com.captureflow.app` suite)
- `PreferencesWindow.swift` — programmatic NSWindow with tier selection, launch at login, stubbed browser/hotkey options
- `LaunchAtLogin.swift` — installs/uninstalls `~/Library/LaunchAgents/com.captureflow.plist`
- `RenameEngine.process()` now returns `@discardableResult URL?` for destination tracking

### Design decisions
- SPM-only (no Xcode project) — `.setActivationPolicy(.accessory)` replaces `LSUIElement` in Info.plist
- SF Symbol `camera.viewfinder` adapts to dark/light mode automatically
- NSMenuDelegate updates toggle title and re-analyze state each time menu opens
- PipelineController extracts DaemonEntry wiring pattern into a class with lifecycle control
- `ssd` daemon target stays for headless/debugging use
- Tier 2/3 and browser URL options visible but disabled in Preferences (future work)

### Test it
```bash
swift build
.build/debug/CaptureFlow
# Camera icon appears in menu bar — take a screenshot to test
```

---

## Step 4 — Batch rename + global hotkey ✅ (2026-03-29)

**Goal:** manual triggers for the naming pipeline — batch rename existing files + global hotkey for quick single-file rename.

### Implemented
- `RenameEngine.processManual(file:)` — manual rename path: skips write-settle delay, debounce, and context lookup; always uses `.empty` context
- `sst --rename` CLI mode — batch rename files in place: `sst --rename file1.png file2.png`
- "Batch Rename Screenshots..." menu item — opens NSOpenPanel (multi-select, PNG/JPEG filter), renames all selected files
- `GlobalHotkeyMonitor` — `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`, filters for configured key combo, renames newest unprocessed screenshot
- Hotkey preferences in `PreferencesStore` — enabled/disabled, keyCode, modifiers (default: Ctrl+Option+S)
- Hotkey checkbox in PreferencesWindow — fully functional, restarts monitor on toggle

### Design decisions
- `processManual` is a separate method from `process(newFile:detectedAt:)` to avoid touching the auto-rename path — no settle delay, no debounce, no context store lookup
- Batch rename creates a fresh `RenameEngine` instance to avoid interfering with the live pipeline's debounce state
- Global hotkey uses `NSEvent.addGlobalMonitorForEvents` (not Carbon `RegisterEventHotKey`) — simpler, Swift-native, sufficient for observe-only use case
- Hotkey finds newest `Screenshot *.png` in the screenshot folder (direct children only, skips subfolders which are already renamed)

### Test it
```bash
# CLI batch rename
sst --rename ~/Desktop/Screenshot*.png

# Menu bar
# Click "Batch Rename Screenshots..." → select files → renamed

# Global hotkey
# Enable in Preferences → press Ctrl+Option+S → newest screenshot renamed
```

---

## Step 5 — Code signing & distribution ✅ (2026-03-29)

**Goal:** wrap SPM binary in a proper `.app` bundle, code sign with Developer ID, notarize, and package as DMG.

### Implemented
- `Distribution/Info.plist` — app bundle metadata (CFBundleIdentifier `com.captureflow.app`, LSUIElement, macOS 13+ minimum)
- `Distribution/CaptureFlow.entitlements` — production entitlements (`automation.apple-events` only, no sandbox, no get-task-allow)
- `Distribution/generate-icon.sh` — converts 1024x1024 PNG to `.icns` via `sips` + `iconutil`
- `scripts/build-and-sign.sh` — full pipeline: release build → .app bundle → codesign → DMG → notarize → staple
- `docs/code-signing.md` — prerequisites, identity setup, build commands, entitlements rationale
- Updated `LaunchAtLogin.swift` fallback path to `/Applications/CaptureFlow.app/Contents/MacOS/CaptureFlow`

### Design decisions
- **Developer ID + Notarization** (not Mac App Store) — App Sandbox conflicts with CGEventTap/Accessibility
- **Hardened Runtime** via `--options runtime` — required for notarization
- **No `get-task-allow`** in production entitlements — debug-only, would fail notarization
- **PlistBuddy version injection** — single source of truth for version at build time
- **DMG with /Applications symlink** — standard drag-to-install UX
- **SPM-only** (no Xcode project) — shell script handles bundling

### Prerequisites
1. **Developer ID Application** certificate (create at developer.apple.com > Certificates)
2. App-specific password for notarization (appleid.apple.com > Security)

### Build & distribute
```bash
# Local testing (skip notarization)
SKIP_NOTARIZE=1 DEVELOPER_ID="Developer ID Application: ..." ./scripts/build-and-sign.sh

# Full distribution build
export DEVELOPER_ID="Developer ID Application: Name (TEAMID)"
export APPLE_ID="you@example.com"
export TEAM_ID="TEAMID"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/build-and-sign.sh
# Output: .build/dist/CaptureFlow-1.0.0.dmg
```

---

## Step 6 — Enhanced naming: FoundationModelsNamer ✅ (2026-04-03)

**Goal:** use Apple's on-device LLM to generate smarter, more descriptive filenames.

### Implemented
- `FoundationModelsNamer` — Tier 2 namer: reuses VisionOnlyNamer.analyze() for OCR + classification, feeds results to Foundation Models LLM
- `@Generable` structured output (ScreenshotName) ensures clean filename format from LLM
- Runtime availability check via `SystemLanguageModel.default.isAvailable`
- Graceful double-fallback: LLM unavailable → Tier 1 slug; LLM fails → Tier 1 slug
- Namer factory in PipelineController + StatusBarController: selects tier based on preference
- Preferences "Naming Mode" dropdown: "Enhanced (Apple Intelligence)" enabled when available
- Tier selection triggers pipeline restart

### Design decisions
- **Text-only LLM** — Foundation Models doesn't accept images; OCR text is extracted first via Vision, then interpreted by LLM
- **Reuse VisionOnlyNamer.analyze()** — no duplicate Vision code; only slug-building differs
- **`#if canImport(FoundationModels)`** — compile-time gating for older SDKs
- **`@available(macOS 26.0, *)`** — runtime gating for older macOS versions

---

## Step 7 — Advanced naming: FastVLMNamer (planned)

- **Tier 3 namer** — uses Apple's FastVLM via MLX for vision-language understanding
- User downloads the model once (~500MB); best offline fallback with multimodal understanding
- Requires Apple Silicon (M1+), macOS 13+
- Opt-in via Preferences — model download prompt on first enable
- Best naming quality: understands image content directly, not just OCR text

---

## Step 8 — Mac App Store distribution ✅ (2026-04-03)

**Goal:** distribute via Mac App Store as a paid app ($4.99). App Sandbox required.

### Implemented
- `#if MAS` conditional compilation: sandbox-incompatible code excluded from MAS build
- `KeystrokeTap` wrapped in `#if !MAS` — CGEventTap forbidden in sandbox
- `GlobalHotkeyMonitor` wrapped in `#if !MAS` — global key monitoring forbidden in sandbox
- NSWorkspace fallback: captures frontmost app in watcher callback (~1-3s delay, 95%+ accuracy)
- `LaunchAtLogin` dual implementation: `#if MAS` uses SMAppService, `#else` uses LaunchAgent
- Security-scoped bookmarks for sandbox folder access persistence
- First-launch NSOpenPanel for screenshot folder selection (MAS only)
- MAS entitlements: App Sandbox + user-selected file access
- `scripts/build-mas.sh` — MAS build pipeline (sign + .pkg)
- `ITSAppUsesNonExemptEncryption = false` in Info.plist
- LicenseManager removed — paid upfront, Apple handles payment

### Design decisions
- **`#if MAS` over runtime detection** — sandbox-incompatible code never ships in MAS binary
- **NSWorkspace in watcher callback** — captures frontmost app at FSEvents time, stores in CaptureContextStore; RenameEngine unchanged
- **Security-scoped bookmarks** — required for folder access persistence in sandbox
- **SMAppService** — Apple's blessed API for launch at login in sandboxed apps (macOS 13+)
- **Paid upfront** — simplest monetization, no StoreKit code needed
- **Both paths preserved** — `swift build` for Developer ID, `swift build -Xswiftc -DMAS` for MAS

### MAS setup (TODO)
1. Create app record in App Store Connect
2. Create "3rd Party Mac Developer Application" and "Installer" certificates
3. Run `scripts/build-mas.sh` and upload .pkg via Transporter

---

## Known gaps / future work

- Browser URL capture (Safari / Chrome / Arc / Firefox via AppleScript)
- Unit tests for `SlugGenerator` and `VisionOnlyNamer.buildSlug`
- **App Store featuring nomination** — Apple lets you nominate your app to be featured: https://developer.apple.com/app-store/getting-featured/ — submit once the app has some reviews and a polished listing. Good candidates: apps using Apple Intelligence, on-device ML, privacy-focused utilities.
- **Pricing strategy** — Launched at $2.99. Revisit after 20-30 reviews. Consider: raise to $4.99 once there's social proof, or go free on MAS and sell direct version via website (keep 95% vs Apple's 70%).
- **Direct distribution monetization** — Sell full-featured (non-sandboxed) version via Gumroad/Paddle on atalaku.studio. MAS listing acts as discovery channel, direct version is the premium product with keystroke tap + global hotkey.
