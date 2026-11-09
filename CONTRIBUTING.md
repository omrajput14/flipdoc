# Contributing & Beta Testing Guide

Thank you for testing and contributing to **MELD** (`TRANSFORM • CONVERT • ORGANIZE`)!

---

## Testing the Pre-App-Store `.dmg` Release

1. Download the latest `MELD-v2.1.0-macOS.dmg` from [**GitHub Releases**](https://github.com/meld-app/meld-mac/releases).
2. Open the `.dmg` and drag **`MELD.app`** into **`Applications`**.
3. Because pre-App-Store beta builds are ad-hoc signed, right-click **`MELD.app`** → **Open** on first launch, or run:
   ```bash
   xattr -cr /Applications/MELD.app && open /Applications/MELD.app
   ```

---

## Building from Source

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Swift 6.0+ (Xcode 16+ or Command Line Tools)

### Commands
```bash
# Run automated unit & integration tests
make test

# Build MELD.app bundle with official MELD Ribbon icon
make app

# Package distributable MELD-v2.1.0-macOS.dmg installer in dist/
make dmg
```

---

## Reporting Bugs or Suggesting Features

- **Bug Reports:** Use the [Bug Report template](https://github.com/meld-app/meld-mac/issues/new?template=bug_report.md) and include your macOS version, input file format, and which radial petal (`⇧ Convert`, `⌘ Tools`, or `⌃ Actions`) you used.
- **Feature Requests:** Use the [Feature Request template](https://github.com/meld-app/meld-mac/issues/new?template=feature_request.md).
