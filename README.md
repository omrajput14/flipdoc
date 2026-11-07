# FlipDoc for Mac

**Zero-click radial file converter, studio toolkit, and floating file shelf for macOS — 100% local & offline.**

Drag any file in Finder (or from any macOS app), tap a modifier key, glide onto a radial petal around your cursor, and release. FlipDoc converts documents, spreadsheets, images, audio, video, subtitles, and archives right beside your original file in milliseconds — with **zero cloud uploads** and **zero Accessibility permissions** required.

---

## Highlights

- **Zero-Click Radial Wheel** — Summon around your cursor mid-drag:
  - **`⇧ Shift` — Convert**: Context-aware format conversions (automatically hides the dragged file's current format).
  - **`⌘ Command` — Tools**: Interactive Compression, Image Resize + Rounded Corners + Studio Backdrop, PDF Split / Merge / Page Organizer, Metadata Inspector & Stripper, Photo Collage, and Apple Vision OCR.
  - **`⌃ Control` — Actions**: Pin to **Float Shelf**, Share via **AirDrop**, Copy File, Move to Folder, Copy Path, or Open in Terminal.
- **Interactive FlipDoc Studio** — Built-in playground with ready-to-drag sample files (`Studio Poster.png`, `Quarterly Invoice.pdf`, `Revenue Metrics.csv`, `Keynote Captions.srt`), live modifier badges, and one-click access to recent conversions.
- **Float Shelf & Desktop Drop Pill** — Temporarily park files from different folders onto a floating glass shelf and drag them out together anywhere.
- **100% Native & Private** — Built with Swift 6, `AppKit`, `SwiftUI`, `PDFKit`, `Vision`, `ImageIO`, `CoreGraphics`, `CoreText`, and `AVFoundation` with zero external Swift package dependencies.

---

## Supported Formats & Tools

| Input Type | Convert (`⇧ Shift`) | Tools (`⌘ Command`) |
| :--- | :--- | :--- |
| **PDF** (`.pdf`) | `.xlsx` (Table Extraction), `.docx`, `.rtf`, `.html`, `.md`, `.txt`, `.png`, `.jpg` | Compress PDF, Organize / Rotate / Delete Pages, Split Pages, Merge PDFs, Vision OCR, Strip Metadata |
| **Images** (`.png`, `.jpg`, `.webp`, `.heic`, `.avif`, `.tiff`, `.bmp`, `.gif`) | `.jpg`, `.png`, `.webp` (offline lossless VP8L), `.heic`, `.avif`, `.tiff`, `.pdf` | Compress Image, Resize & Frame (Corners + Padding), Photo Collage (2+ images), Combine to PDF, Vision OCR, Strip EXIF/GPS |
| **Spreadsheets** (`.xlsx`, `.xls`, `.csv`, `.tsv`) | `.pdf` (Paginated Vector Table), `.xlsx`, `.csv`, `.tsv`, `.md` | Multi-column auto-width layout & landscape switch for wide sheets |
| **Documents** (`.docx`, `.rtf`, `.txt`, `.md`, `.html`) | `.pdf`, `.docx`, `.rtf`, `.html`, `.md`, `.txt` | Paginated CoreText vector PDF rendering |
| **Video** (`.mp4`, `.mov`, `.m4v`, `.mkv`, `.webm`) | `.mp4`, `.mov`, Animated `.gif`, `.m4a` (audio), `.wav` (audio) | Compress Video, Mute Audio Track (lossless passthrough), Save PNG Snapshots |
| **Audio** (`.mp3`, `.m4a`, `.wav`, `.flac`, `.aiff`, `.aac`) | `.m4a`, `.wav`, `.aiff`, `.flac` | Convert to Mono |
| **Subtitles** (`.srt`, `.vtt`) | `.srt`, `.vtt`, Clean `.txt` Transcript | Timestamp normalization & HTML tag cleanup |
| **Archives & Folders** (`.zip`, `.tar`, `.tar.gz`, folders) | `.zip`, `.tar.gz`, `.tar` | Extract Archive to sibling folder |

---

## Quick Start

### Requirements
- **macOS 14.0 (Sonoma)** or newer
- **Swift 6.0+** (Xcode 16+ or macOS Command Line Tools)

### Build & Run `FlipDoc.app`

```bash
# Clone repository
git clone https://github.com/omrajput14/flipdoc.git
cd flipdoc

# Package & sign FlipDoc.app (release build + generated AppIcon.icns)
make app

# Launch FlipDoc
open FlipDoc.app
```

### Run Automated Test Suite

```bash
make test
# or directly via SwiftPM:
swift test
```

---

## Project Structure

```text
flipdoc/
├── Config/Info.plist                    # macOS accessory bundle metadata
├── Docs/
│   ├── ARCHITECTURE.md                  # Module boundaries & execution pipeline
│   └── PRD.md                           # Product specification
├── Scripts/build-app.sh                 # Release .app bundler, icon generator & codesigner
├── Sources/
│   ├── FlipDoc/main.swift               # Executable entry point
│   └── FlipDocCore/
│       ├── App/                         # AppDelegate, MenuBarController, ActionDispatcher
│       ├── Core/                        # FileCategory, OutputNaming, AppPreferences, SoundAndHaptics
│       ├── Engines/
│       │   ├── Document/                # DocumentTools, PDFTableExtractor, XLSXtoPDFEngine, PDFMarkdownConverter
│       │   ├── Image/                   # ImageTransformer (incl. offline VP8L WebP), VisionOCREngine
│       │   └── Media/                   # MediaConverter (AVFoundation Video/GIF & afconvert Audio)
│       ├── Overlay/                     # GlobalDragMonitor, PetalGeometry, RadialFanView, FloatingDropZoneWindow
│       └── UI/                          # FlipDocTheme, PlaygroundDashboardWindow, FloatingShelfWindow, ToolOptionsWindow
├── Tests/FlipDocTests/                  # End-to-end unit & engine integration tests
├── Makefile
└── Package.swift
```

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and [Docs/PRD.md](Docs/PRD.md) for deeper technical details.

---

## License

MIT
