# SmartScreenShot — Code Signing & Distribution

## Distribution model

Developer ID + Notarization (outside Mac App Store).

**Why not the Mac App Store?**
- App Sandbox is required for MAS distribution
- CGEventTap (used by KeystrokeTap) is incompatible with App Sandbox
- Menu bar utilities that need Accessibility permission are a poor fit for MAS

## Prerequisites

1. Active Apple Developer Program membership ($99/year)
2. **Developer ID Application** certificate installed in Keychain
3. App-specific password for notarization (appleid.apple.com > Security > App-Specific Passwords)

## Getting a Developer ID certificate

1. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click "+" to create a new certificate
3. Select "Developer ID Application"
4. Follow the CSR generation steps
5. Download and double-click to install in Keychain

## Find your signing identity

```bash
security find-identity -v -p codesigning
```

Look for: `Developer ID Application: Your Name (TEAMID)`

## Build & distribute

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export TEAM_ID="TEAMID"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./scripts/build-and-sign.sh
```

Output: `.build/dist/SmartScreenShot-1.0.0.dmg`

## Local testing (skip notarization)

```bash
SKIP_NOTARIZE=1 DEVELOPER_ID="Apple Development: ..." ./scripts/build-and-sign.sh
```

## Version bumping

```bash
VERSION=1.1.0 DEVELOPER_ID="..." ./scripts/build-and-sign.sh
```

The version is injected into Info.plist at build time via PlistBuddy.

## Entitlements

| Entitlement | Included | Reason |
|---|---|---|
| `automation.apple-events` | Yes | Future browser URL capture via AppleScript |
| `cs.allow-unsigned-executable-memory` | No | Vision framework uses Apple's own signed code |
| `get-task-allow` | No | Debug-only; would fail notarization |
| `app-sandbox` | No | Conflicts with CGEventTap |

## Hardened Runtime

Enabled via `--options runtime` during codesign. Required for notarization.
The app does not use any APIs that conflict with Hardened Runtime.

## App bundle structure

```
SmartScreenShot.app/
  Contents/
    Info.plist          (bundle ID, version, LSUIElement)
    MacOS/
      SmartScreenShot   (release binary, code-signed)
    Resources/
      AppIcon.icns      (optional, from generate-icon.sh)
```

## LaunchAgent

The LaunchAgent plist (`~/Library/LaunchAgents/com.smartscreenshot.plist`) uses
`Bundle.main.executablePath` to resolve the binary path. When running from a `.app`
bundle, this correctly resolves to:
`/Applications/SmartScreenShot.app/Contents/MacOS/SmartScreenShot`
