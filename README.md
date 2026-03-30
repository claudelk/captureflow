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

Menu options: Enable/Disable, Re-analyze Last Screenshot, Batch Rename Screenshots, Open Screenshot Folder, Preferences, Quit.

### CLI

```bash
# Print slug for a screenshot
.build/debug/sst screenshot.png

# Verbose: show OCR lines, scores, classification labels
.build/debug/sst screenshot.png --verbose

# Batch rename existing screenshots
.build/debug/sst --rename screenshot1.png screenshot2.png
.build/debug/sst --rename ~/Desktop/Screenshot*.png
```

### Daemon (headless, for debugging)

```bash
.build/debug/ssd
```

---

## Distribution

Build a signed, notarized `.dmg` for distribution:

```bash
# Local testing (skip notarization)
SKIP_NOTARIZE=1 DEVELOPER_ID="Developer ID Application: ..." ./scripts/build-and-sign.sh

# Full distribution build
export DEVELOPER_ID="Developer ID Application: Name (TEAMID)"
export APPLE_ID="you@example.com"
export TEAM_ID="TEAMID"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/build-and-sign.sh
```

See [docs/code-signing.md](docs/code-signing.md) for prerequisites and setup.

---

## Roadmap

- **Step 1** ✅ CLI naming brain (`sst`) — Vision OCR + scene classification
- **Step 2** ✅ Background daemon (`ssd`) — CGEventTap + FSEvents + RenameEngine
- **Step 3** ✅ Menu bar app (`SmartScreenShot`) — NSStatusItem + preferences + launch at login
- **Step 4** ✅ Batch rename (menu bar + CLI) + global hotkey
- **Step 5** ✅ Code signing & notarization (Developer ID + DMG)
- **Step 6** Enhanced naming — `FoundationModelsNamer` (macOS 26+, Apple Intelligence)
- **Step 7** Advanced naming — `FastVLMNamer` (Apple Silicon, on-device VLM via MLX)
- **Step 8** Trial / paid licensing (5/day free, $4.99 lifetime unlock)
