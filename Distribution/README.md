# Distribution

Files for building, signing, and packaging SmartScreenShot for distribution.

## Files

| File | Purpose |
|---|---|
| `Info.plist` | App bundle metadata (bundle ID, version, LSUIElement) |
| `SmartScreenShot.entitlements` | Production entitlements for code signing |
| `generate-icon.sh` | Converts a 1024x1024 PNG into AppIcon.icns |
| `AppIcon-1024.png` | Source icon (you provide this) |
| `AppIcon.icns` | Generated icon (output of generate-icon.sh) |

## Workflow

1. Place your 1024x1024 icon at `Distribution/AppIcon-1024.png`
2. Run `./Distribution/generate-icon.sh` to create the `.icns`
3. Run `./scripts/build-and-sign.sh` to build, sign, and package

See `docs/code-signing.md` for full instructions.
