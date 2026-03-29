# SmartScreenShot Daemon — Design Notes

The `ssd` binary is the always-on background agent that connects keystroke context to file rename.

---

## The timing problem

By the time a new screenshot file appears on disk, macOS has already shifted focus away from
the captured app. `NSWorkspace.frontmostApplication` at FSEvents fire time is the wrong app.

**Solution:** CGEventTap + timestamp matching.

---

## Event flow

```
User presses Cmd+Shift+3/4/5
        │
        ▼
KeystrokeTap (CGEventTap, main RunLoop)
  - NSWorkspace.frontmostApplication → appName, bundleID
  - Date.now → capturedAt
  - store.store(context)  ← synchronous, lock-based
        │
        ▼                           (0–2 s later)
ScreenshotWatcher (FSEvents, main RunLoop)
  - New .png detected in screenshot folder
  - onNewFile(url) → Task { await engine.process(url) }
        │
        ▼
RenameEngine (actor)
  - sleep 0.5 s  (let macOS finish writing)
  - store.nearest(to: fileCreationDate, within: 5 s)
  - VisionOnlyNamer.name(image:context:) → contentSlug
  - appSlug = SlugGenerator.slug(from: context.appName)
  - mkdir  {folder}/{appSlug}_{YYYY-MM-DD}/
  - move   {original} → {appSlug}_{YYYY-MM-DD}/{contentSlug}_{HH-mm-ss}.png
```

---

## Context matching window

`CaptureContextStore` is a lock-based class (`NSLock`, not an actor) so the
CGEventTap callback can store contexts **synchronously** — guaranteeing the
context is available by the time `RenameEngine` queries it. This eliminates the
race condition where an async `store()` Task hadn't completed before `nearest()`.

`nearest(to:within:)` returns the context whose `capturedAt` is closest to the
event detection time, within a 5-second window. Entries older than 10 seconds
are pruned on each write.

---

## Folder filtering

`ScreenshotWatcher` only fires for **direct children** of the watched folder.
Files that land in app-slug subfolders (after rename) are automatically ignored.

---

## Collision handling

If two screenshots happen in the same second with the same content slug, `RenameEngine`
appends a counter: `slug_HH-mm-ss_1.png`, `slug_HH-mm-ss_2.png`, etc.

---

## Permissions required

- **Accessibility** — required for CGEventTap to see keyboard events from other apps.
  Grant in System Settings › Privacy & Security › Accessibility.
- **Full Disk Access** (optional) — needed only if the screenshot folder is outside `~/Desktop`.

---

## Running the daemon

```bash
swift build
.build/debug/ssd
```

On first run without Accessibility permission, the system prompt is triggered automatically.
After granting access, re-run `ssd`.
