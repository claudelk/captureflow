# VisionOnlyNamer — Design Notes

Tier 1 of the `ImageNamer` protocol hierarchy. Ships in v1.

---

## What it does

Runs two Vision requests concurrently on the screenshot:

1. **`VNRecognizeTextRequest`** (`.accurate` mode)
   Extracts all text visible in the screenshot with per-line confidence scores.
   Languages: system-preferred + `en-US` as fallback.

2. **`VNClassifyImageRequest`**
   Returns scene/object labels (`beach`, `chess board`, `food`, `vehicle`, …) with confidence scores.
   Used as fallback when OCR yields nothing useful.

---

## Slug selection algorithm

```
1. Filter OCR lines: confidence > 0.3
2. Score each line with SlugGenerator.meaningScore()
   - Base score = character count
   - +2 per alphabetic character (rewards content over noise)
   - -15 if all-caps (UI labels: "OK", "CANCEL", "FILE")
   - -20 if < 5 chars
   - -10 if < 40% alphabetic ratio (timestamps, hex, etc.)
3. Pick highest-scoring line; if score > 5, slugify it → done
4. Fallback: top VNClassificationObservation label (skip "others_*")
   Convert underscores to spaces, then slugify → done
5. Ultimate fallback: "untitled"
```

---

## SlugGenerator.slug()

- Lowercase
- Strip non-alphanumeric chars (keep spaces)
- Collapse whitespace → hyphens
- Collapse `--` → `-`
- Strip leading/trailing hyphens
- Truncate to 50 chars at last word boundary

---

## Why not use VNRecognizeTextRequest revision 3 explicitly?

Revision is auto-selected by Vision based on the OS version. On macOS 13+ this gives
the best available model without hardcoding a revision that may be removed in future OS versions.

---

## Tier roadmap

| Tier | Class | Gap this fills |
|---|---|---|
| 1 | `VisionOnlyNamer` | Any Mac, any screenshot with text or identifiable scene |
| 2 | `FoundationModelsNamer` | Richer names on macOS 26+ — LLM generates creative slugs from Vision descriptors |
| 3 | `FastVLMNamer` | Pre-macOS 26 Apple Silicon — true VLM understanding for game screenshots, photos, charts |

All three conform to `ImageNamer`. Runtime selection is a single factory function.
