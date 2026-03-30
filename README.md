# SmartScreenShot

macOS menu bar utility that automatically renames screenshots with meaningful names.

**Before:** `Screenshot 2026-03-29 at 10.12.07.png`
**After:** `figma_2026-03-29/auto-layout-component_10-12-07.png`

---

## Output format

```
{app-name-slug}_{YYYY-MM-DD}/
  {content-slug}_{HH-mm-ss}.png
```

One folder per app per day. Content slug comes from Vision OCR on the screenshot,
with scene classification as fallback.

---

## Architecture

Protocol-based namer tiers — works on every Mac shipping today, gets smarter on newer hardware:

| Tier | Namer | When used |
|---|---|---|
| 1 | `VisionOnlyNamer` | Always (macOS 13+) — OCR + scene labels |
| 2 | `FoundationModelsNamer` | macOS 26+ with Apple Intelligence |
| 3 | `FastVLMNamer` | Apple Silicon, opt-in, v2 |

---

## Build

Requires Xcode 15+ / Swift 5.9+, macOS 13+.

```bash
swift build
swift build -c release
```

---

## Usage

### Menu bar app (recommended)

```bash
swift build
.build/debug/SmartScreenShot
```

A camera icon appears in the menu bar. Take a screenshot (Cmd+Shift+3/4/5) and it gets
automatically renamed and organized.

Menu options: Enable/Disable, Re-analyze Last Screenshot, Open Screenshot Folder, Preferences, Quit.

### CLI (naming brain only)

```bash
# Print slug for a screenshot
.build/debug/sst screenshot.png

# Verbose: show OCR lines, scores, classification labels
.build/debug/sst screenshot.png --verbose
```

### Daemon (headless, for debugging)

```bash
.build/debug/ssd
```

---

## Roadmap

- **Step 1** ✅ CLI naming brain (`sst`) — Vision OCR + scene classification
- **Step 2** ✅ Background daemon (`ssd`) — CGEventTap + FSEvents + RenameEngine
- **Step 3** ✅ Menu bar app (`SmartScreenShot`) — NSStatusItem + preferences + launch at login
- **Step 4** Finder Quick Action (batch rename) + global hotkey
- **Step 5** Code signing & notarization (Developer ID)
- **Step 6** Enhanced naming — `FoundationModelsNamer` (macOS 26+, Apple Intelligence)
- **Step 7** Advanced naming — `FastVLMNamer` (Apple Silicon, on-device VLM via MLX)
