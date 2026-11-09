#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-v2.1.0}"
DMG_NAME="MELD-${VERSION}-macOS.dmg"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="$(mktemp -d)"

echo "==> Step 1: Building MELD.app..."
"${ROOT_DIR}/Scripts/build-app.sh"

echo "==> Step 2: Preparing DMG staging directory..."
mkdir -p "$DIST_DIR"
cp -R "${ROOT_DIR}/MELD.app" "${STAGING_DIR}/MELD.app"
ln -s /Applications "${STAGING_DIR}/Applications"

cat > "${STAGING_DIR}/Read Me — Beta Tester Guide.txt" << 'EOF'
MELD for macOS — Pre-App-Store Beta Build
TRANSFORM • CONVERT • ORGANIZE (100% Local & Offline)

INSTALLATION
1. Drag MELD.app into the Applications folder.
2. First launch (Pre-App-Store Beta):
   Right-click (or Control-click) MELD.app in Applications and choose "Open",
   OR run this one-liner in Terminal if macOS Gatekeeper blocks first launch:
     xattr -cr /Applications/MELD.app && open /Applications/MELD.app

HOW TO USE MELD
• Drag any file in Finder and tap:
  - ⇧ Shift   → Convert formats (PNG, WEBP, HEIC, XLSX, DOCX, PDF, MP4, GIF, M4A, WAV...)
  - ⌘ Command → Quick Tools (Remove BG, Target Size Compress <200KB/<500KB/<1MB/<2MB,
                PDF Lock & Stamp, 3-Up Study Handout, Scan QR, Redact PII, OCR, Resize...)
  - ⌃ Control → File Actions (Pin to Float Shelf, AirDrop, Copy, Move, Copy Path, Terminal)

FOUND A BUG OR HAVE FEEDBACK?
Open an issue at: https://github.com/meld-app/meld-mac/issues
EOF

rm -f "${DIST_DIR}/${DMG_NAME}"

echo "==> Step 3: Creating compressed disk image ${DIST_DIR}/${DMG_NAME}..."
hdiutil create \
    -volname "MELD ${VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "${DIST_DIR}/${DMG_NAME}"

rm -rf "$STAGING_DIR"

shasum -a 256 "${DIST_DIR}/${DMG_NAME}" > "${DIST_DIR}/${DMG_NAME}.sha256"
echo "==> Built DMG: ${DIST_DIR}/${DMG_NAME}"
cat "${DIST_DIR}/${DMG_NAME}.sha256"
