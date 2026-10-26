# FlipDoc for Mac 

> **The zero-click offline document & file transformer.**  
> Drag a file, tap `Shift` to convert, `Command` for document tools, or `Control` for quick actions. Everything runs 100% locally on your Mac.

---

## ✨ Features

- **Zero-Click Drag & Drop**: Drag any file, tap a key, and drop onto the radial fan overlay.
  - `⇧ Shift` → Format Conversions (PDF to Excel tables, Markdown, PNG/JPG, text).
  - `⌘ Command` → Document Tools (Table extraction, OCR text recognition, PDF compression).
  - `⌃ Control` → Quick Actions (Float preview, AirDrop, Copy path, Terminal).
- **100% Offline & Private**: Zero uploads, no internet connection required.
- **Native Apple Silicon Speed**: Built in Swift 6, AppKit, SwiftUI, PDFKit, and Apple Vision.
- **Dual Mode**: Runs as a lightweight menu bar daemon (`LSUIElement`) or directly from the CLI.

---

## 🛠️ Build & Run

### Requirements
- macOS 13.0+ (Ventura, Sonoma, Sequoia)
- Swift 6.0+

```bash
# Build the project
swift build -c release

# Launch the menu bar background agent
.build/release/FlipDoc

# Or use the CLI for batch conversions:
.build/release/FlipDoc tables invoice.pdf       # extracts tables to invoice.xlsx
.build/release/FlipDoc markdown document.pdf     # converts PDF to document.md
```

---

## 📋 Documentation
See [`PRD.md`](./PRD.md) for complete technical architecture, conversion matrix, and roadmap.
