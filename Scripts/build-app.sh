#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="FlipDoc"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} (release)..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Assembling ${APP_NAME}.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/Config/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Generate crisp macOS AppIcon.icns dynamically via CoreGraphics + iconutil
TMP_ICON_DIR="$(mktemp -d)"
ICONSET_DIR="${TMP_ICON_DIR}/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT'
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let iconsetPath = CommandLine.arguments[1]
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in sizes {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }

    let pad = s * 0.09
    let cardRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let corner = s * 0.225
    let bgPath = CGPath(roundedRect: cardRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradColors = [
        CGColor(srgbRed: 1.0, green: 0.42, blue: 0.08, alpha: 1.0),
        CGColor(srgbRed: 0.96, green: 0.26, blue: 0.0, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: pad, y: s - pad),
            end: CGPoint(x: s - pad, y: pad),
            options: []
        )
    }
    ctx.restoreGState()

    // Radial wheel motif inside squircle
    let center = CGPoint(x: s / 2.0, y: s / 2.0)
    let outerR = s * 0.30
    let innerR = s * 0.135
    let count = 6
    let gap = 0.09
    for idx in 0..<count {
        let step = (2.0 * Double.pi) / Double(count)
        let a0 = CGFloat(Double(idx) * step + gap / 2.0)
        let a1 = CGFloat(Double(idx + 1) * step - gap / 2.0)
        let path = CGMutablePath()
        path.addArc(center: center, radius: innerR, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: center, radius: outerR, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: idx == 1 ? 1.0 : 0.84))
        ctx.fillPath()
    }

    let url = URL(fileURLWithPath: iconsetPath).appendingPathComponent(filename)
    if let cg = ctx.makeImage(),
       let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}
SWIFT

if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "$ICONSET_DIR" -o "${RESOURCES_DIR}/AppIcon.icns" || true
fi
rm -rf "$TMP_ICON_DIR"

echo "==> Code-signing ${APP_NAME}.app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Built ${APP_BUNDLE}"
