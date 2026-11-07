# FlipDoc for Mac — Product Requirements Document (PRD)

**Product Name:** FlipDoc  
**Platform:** Native macOS 14.0+ (`Swift 6.0`, `AppKit`, `SwiftUI`)  
**Privacy & Execution Model:** 100% Offline, Zero Cloud Uploads, Non-Destructive Output Naming

---

## 1. Product Vision

FlipDoc turns macOS file conversions, quick media/document tools, and file actions into a single fluid drag-and-drop gesture. Instead of opening heavy standalone apps or uploading private documents to web converters, users drag any file anywhere on macOS, tap a modifier key (`⇧ Shift`, `⌘ Command`, or `⌃ Control`), glide onto a radial petal around the cursor, and release.

---

## 2. Core Interaction Model

1. **Accessibility-Free Global Drag Detection (`GlobalDragMonitor`)**
   - Observes system drag pasteboard changes (`NSPasteboard(name: .drag).changeCount`) paired with `CGEventSource` button and modifier state — requiring **zero Accessibility (TCC) permissions** and never intercepting normal typing shortcuts.
2. **Three Instant Radial Modes**
   - **`⇧ Shift` — Convert**: Context-aware format targets (automatically hides the input file's own extension).
   - **`⌘ Command` — Tools**: Compression, image resize/corner-radius/backdrop framing, PDF split/merge/page organizer, EXIF/PDF metadata inspector & stripper, Apple Vision OCR, photo collage, video mute/snapshots.
   - **`⌃ Control` — Actions**: Float Shelf pinning, AirDrop, Copy to Clipboard, Move to Folder, Copy File Path, Open in Terminal.
3. **Interactive Studio & Desktop Drop Pill**
   - **`FlipDoc Studio` (`PlaygroundDashboardWindow`)**: Built-in interactive sandbox with auto-generated sample files (`Studio Poster.png`, `Quarterly Invoice.pdf`, `Revenue Metrics.csv`, `Keynote Captions.srt`), live modifier indicators, and recent conversion history.
   - **Floating Drop Pill (`FloatingDropZoneWindow`)** & **Float Shelf (`FloatingShelfWindow`)**: Non-activating glass overlays for pinning files across spaces and dragging multiple items out together.

---

## 3. Supported Workflows & Engines

| Category | Formats & Conversions (`⇧`) | Built-In Tools (`⌘`) | Native Frameworks |
| :--- | :--- | :--- | :--- |
| **PDF** | `.xlsx` (table extraction), `.docx`, `.rtf`, `.html`, `.md`, `.txt`, `.png`, `.jpg` | Split Pages, Merge PDFs, Organize/Rotate/Delete Pages, Compress PDF, Strip Metadata, Vision OCR | `PDFKit`, `Vision`, `CoreGraphics` |
| **Images** | `.png`, `.jpg`, `.webp` (offline lossless VP8L), `.heic`, `.avif`, `.tiff`, `.bmp`, `.pdf` | Compress Quality, Resize + Round Corners + Backdrop Frame, Strip EXIF/GPS Metadata, Photo Collage, Vision OCR | `ImageIO`, `CoreGraphics`, `Vision` |
| **Spreadsheets** | `.pdf` (paginated vector A4/landscape), `.xlsx`, `.csv`, `.tsv`, `.md` | RFC-4180 CSV/TSV parser + native OOXML `.xlsx` reader/writer (`A`..`ZZ+` columns) | `CoreText`, `XMLParser`, `/usr/bin/ditto` |
| **Documents** | `.pdf`, `.docx`, `.rtf`, `.html`, `.md`, `.txt` | Paginated CoreText vector PDF rendering | `CoreText`, `/usr/bin/textutil` |
| **Video** | `.mp4`, `.mov`, Animated `.gif`, Extract `.m4a` / `.wav` | Compress Video, Mute Audio Track (passthrough), Save 6 PNG Snapshots | `AVFoundation`, `ImageIO` |
| **Audio** | `.m4a`, `.wav`, `.aiff`, `.flac` | Downmix to Mono | `/usr/bin/afconvert` (+ optional `ffmpeg`) |
| **Subtitles** | `.srt` ↔ `.vtt`, Clean `.txt` transcript | Timestamp normalization & HTML tag stripping | `Foundation` Regular Expressions |
| **Archives & Folders** | `.zip`, `.tar`, `.tar.gz` | Extract Archive into clean sibling folder | `/usr/bin/ditto`, `/usr/bin/zip`, `/usr/bin/tar` |

---

## 4. Non-Functional Guarantees

- **Non-Destructive File Safety**: `OutputNaming` never overwrites an existing file or folder — collisions automatically increment (`Report 2.pdf`, `Report 3.pdf`).
- **Tactile & Audio Polish**: Synthesized 14ms crisp tick audio + Force Touch alignment haptics (`NSHapticFeedbackManager`) on petal hover and completion.
- **Zero External Swift Dependencies**: Pure Swift 6 standard/Apple system frameworks for fast builds and compact binary size.
