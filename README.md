# JustNow

A native macOS menu bar app that continuously captures screenshots and lets you scroll back through the last 5-10 minutes of screen history via a hotkey-triggered fullscreen overlay.

## Features

- **Continuous capture**: Captures screenshots every 0.5 to 5 seconds
- **Perceptual hashing**: Skips near-identical frames to save memory (30-50% savings)
- **Exponential decay**: Recent frames kept at full density, older frames thinned out
- **Recent detail**: Browse the newest 1, 2, or 5 minutes using every stored frame before older history is collapsed
- **Battery conscious**: Can reduce quality/background work on battery without changing your chosen cadence
- **Fullscreen overlay**: Press ⌘⌥J to view timeline, scroll/drag to navigate
- **Menu bar only**: Runs silently with no dock icon

## Requirements

- macOS 26+
- Screen Recording permission

## Usage

1. Launch JustNow - it appears in the menu bar
2. Grant Screen Recording permission when prompted
3. Let it run to build up history
4. Press **⌘⌥J** to open the timeline overlay
5. Scroll horizontally or drag to navigate through time
6. Press **Escape** to dismiss

## Settings

Access via menu bar icon → Settings:

- **Capture interval**: 0.5s to 5s (default 0.5s)
- **Newest timeline detail**: 1, 2, or 5 minutes at full capture detail
- **Max frames**: 100 to 1200 (default 600, ~10 min at 1fps)
- **Battery mode**: Optional cadence preservation when unplugged

## Architecture

```
ScreenCaptureKit → Perceptual Hash Filter → Ring Buffer (RAM)
                                                    ↓
                                          Retention Manager
                                          (exponential decay)
```

## Building

Open `JustNow.xcodeproj` in Xcode and build (⌘B), or:

```bash
xcodebuild -scheme JustNow -configuration Release -derivedDataPath build
```

## Releases

GitHub releases are published from version tags. Latest release:

- v0.1 (first release)

You can download the build from the release assets.

## DMG packaging

Release builds are assembled with `create-dmg` in CI to include:

- the app icon
- a styled install window layout with an Applications drop target arrow
- optional custom background image when `Assets/Release/dmg-background.png` exists

## Release signing (GitHub Actions)

Public release artifacts are signed and notarized in CI.

Set the following repository secrets before tagging a release:

- `APPLE_TEAM_ID` (example: `PQ6U5ESLN2`)
- `APPLE_SIGNING_IDENTITY` (example: `Developer ID Application: Your Name (PQ6U5ESLN2)`)
- `APPLE_SIGNING_CERTIFICATE_P12` (base64-encoded `.p12`)
- `APPLE_SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_API_KEY` (base64-encoded `.p8`)
- `APPLE_API_KEY_ID`
- `APPLE_API_KEY_ISSUER_ID`

When these secrets are configured, release jobs:

- build with `CODE_SIGN_STYLE=Manual`
- sign app + DMG with Developer ID
- notarize the DMG
- staple it
- upload the signed artifacts to GitHub Releases

If the secrets are missing, the workflow now fails early with a clear error.

## Licence

MIT
