# SmartScreenShot — Project Structure

macOS menu bar utility that automatically renames screenshots with meaningful names
instead of macOS's default "Screenshot 2026-03-29 at 1.19.49 PM" format.

---

## Root

| File / Folder | Purpose |
|---|---|
| `Package.swift` | SPM package — three targets: `sst` (CLI), `ssd` (daemon), `SmartScreenShotCore` (library) |
| `README.md` | Project overview, build instructions, usage |
| `PROGRESS.md` | Phase-by-phase implementation log and next steps |
| `CLAUDE.md` | This file — canonical project structure |
| `docs/` | Per-feature design docs (one .md per major component) |
| `Sources/` | All Swift source code |

---

## Sources/Core/ — `SmartScreenShotCore` library target

| File | Purpose |
|---|---|
| `ImageNamer.swift` | `ImageNamer` protocol + `CaptureContext` struct |
| `SlugGenerator.swift` | Slug cleaning (`slug(from:)`) + OCR line scoring (`meaningScore(for:)`) |
| `VisionOnlyNamer.swift` | Tier 1 namer: VNRecognizeTextRequest (OCR) + VNClassifyImageRequest (scene labels) |
| `CaptureContextStore.swift` | Lock-based ring buffer of keystroke contexts, synchronous store + nearest-match lookup |
| `ScreenshotPreferences.swift` | Reads `com.apple.screencapture location` pref; falls back to `~/Desktop` |
| `KeystrokeTap.swift` | CGEventTap wrapper: listens for Cmd+Shift+3/4/5, captures frontmost app |
| `ScreenshotWatcher.swift` | FSEvents wrapper: fires when a new PNG appears in the screenshot folder |
| `RenameEngine.swift` | Actor: matches context → names image → creates folder → moves file |

---

## Sources/CLI/ — `sst` executable target

| File | Purpose |
|---|---|
| `Entry.swift` | `@main` entry: takes image path, runs VisionOnlyNamer, prints slug |

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

---

## Namer tier roadmap

| Tier | Class | Availability | Status |
|---|---|---|---|
| 1 | `VisionOnlyNamer` | macOS 13+, all hardware | **Shipped in v1** |
| 2 | `FoundationModelsNamer` | macOS 26+, Apple Intelligence | Planned v2 |
| 3 | `FastVLMNamer` | macOS 13+, Apple Silicon, opt-in | Planned v2 |

---

## Output format

```
{screenshot-folder}/
  {app-name-slug}_{YYYY-MM-DD}/
    {content-slug}_{HH-mm-ss}.png
```
