# CaptureFlow — Project Structure

macOS menu bar utility that automatically renames screenshots with meaningful names
instead of macOS's default "Screenshot 2026-03-29 at 1.19.49 PM" format.

---

## Root

| File / Folder | Purpose |
|---|---|
| `Package.swift` | SPM package — four targets: `sst` (CLI), `ssd` (daemon), `CaptureFlow` (menu bar app), `CaptureFlowCore` (library) |
| `README.md` | Project overview, build instructions, usage |
| `PROGRESS.md` | Phase-by-phase implementation log and next steps |
| `CLAUDE.md` | This file — canonical project structure |
| `docs/` | Per-feature design docs (one .md per major component) |
| `Sources/` | All Swift source code |
| `Distribution/` | Info.plist, entitlements, icon generation for .app bundle |
| `scripts/` | Build, sign, notarize, and package scripts |

---

## Sources/Core/ — `CaptureFlowCore` library target

| File | Purpose |
|---|---|
| `ImageNamer.swift` | `ImageNamer` protocol + `CaptureContext` struct |
| `SlugGenerator.swift` | Slug cleaning (`slug(from:)`) + OCR line scoring (`meaningScore(for:)`) |
| `VisionOnlyNamer.swift` | Tier 1 namer: VNRecognizeTextRequest (OCR) + VNClassifyImageRequest (scene labels) |
| `FoundationModelsNamer.swift` | Tier 2 namer: Vision OCR + Apple Intelligence LLM (`#if canImport(FoundationModels)`, macOS 26+) |
| `CaptureContextStore.swift` | Lock-based ring buffer of keystroke contexts, synchronous store + nearest-match lookup |
| `ScreenshotPreferences.swift` | Reads `com.apple.screencapture location` pref; falls back to `~/Desktop` |
| `MigrationEngine.swift` | Scans for Apple-default-named files + legacy folders, organizes into root folder |
| `KeystrokeTap.swift` | CGEventTap wrapper: listens for Cmd+Shift+3/4/5, captures frontmost app |
| `ScreenshotWatcher.swift` | FSEvents wrapper: fires when a new PNG appears in the screenshot folder |
| `RenameEngine.swift` | Actor: `process()` for auto-rename with context, `processManual()` for batch/manual rename without context |

---

## Sources/App/ — `CaptureFlow` executable target (menu bar app)

| File | Purpose |
|---|---|
| `AppEntry.swift` | `@main` entry: NSApplication with `.accessory` policy, Accessibility check via NSAlert, wires components |
| `PipelineController.swift` | Orchestration layer: wraps KeystrokeTap + ScreenshotWatcher + RenameEngine with start/stop lifecycle |
| `StatusBarController.swift` | NSStatusItem + NSMenu: Enable/Disable, Re-analyze Last, Batch Rename, Open Folder, Preferences, Quit |
| `PreferencesStore.swift` | UserDefaults wrapper for all settings + security-scoped bookmark support for MAS sandbox |
| `PreferencesWindow.swift` | Programmatic NSWindow: tier selection, launch at login, global hotkey toggle (`#if !MAS`), browser capture stub |
| `LaunchAtLogin.swift` | `#if MAS`: SMAppService; `#else`: LaunchAgent plist |
| `GlobalHotkeyMonitor.swift` | NSEvent global key monitor (`#if !MAS` only) |

---

## Sources/CLI/ — `sst` executable target

| File | Purpose |
|---|---|
| `Entry.swift` | `@main` entry: `sst <image>` prints slug, `sst --rename <files...>` batch renames |

---

## Sources/Daemon/ — `ssd` executable target

| File | Purpose |
|---|---|
| `DaemonEntry.swift` | `@main` entry: wires KeystrokeTap + ScreenshotWatcher + RenameEngine, runs RunLoop |

---

## docs/

| File | Purpose |
|---|---|
| `vision-only-namer.md` | Tier 1 design, slug algorithm, tier roadmap |
| `daemon.md` | Step 2 daemon design: event flow, timing strategy, folder structure |
| `menu-bar-app.md` | Step 3 menu bar app: NSStatusItem, preferences, launch at login |
| `code-signing.md` | Step 5 code signing, notarization, DMG distribution |
| `licensing.md` | Distribution paths: direct (Developer ID) vs MAS (sandbox), conditional compilation |

---

## Namer tier roadmap

| Tier | Class | Availability | Status |
|---|---|---|---|
| 1 | `VisionOnlyNamer` | macOS 13+, all hardware | **Shipped in v1** |
| 2 | `FoundationModelsNamer` | macOS 26+, Apple Intelligence | **Shipped in v2** |
| 3 | `FastVLMNamer` | macOS 13+, Apple Silicon, opt-in | Planned v2 |

---

## Output format

```
{screenshot-folder}/
  {root-folder}/                  (default: "Screenshots", localized, configurable)
    {locale-date}/                (system locale short date, e.g. "2026-04-07" or "07-04-2026")
      images/                     (localized: "images", "imágenes", etc.)
        {content-slug}_{HH-mm-ss}.png
      videos/                     (localized: "videos", "vídeos", etc.)
        {recording-slug}_{HH-mm-ss}.mov
```

Legacy mode (empty root folder name):
```
{screenshot-folder}/
  {app-name-slug}_{YYYY-MM-DD}/
    {content-slug}_{HH-mm-ss}.png
```
