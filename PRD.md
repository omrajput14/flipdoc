# FlipDoc — Product Requirements Document (PRD)

**Product Name:** FlipDoc for Mac  
**Tagline:** The zero-click offline document & file transformer.  
**Platform:** macOS 13.0+ (Ventura, Sonoma, Sequoia) — Apple Silicon (`arm64`)  
**Technology:** Native Swift 6, AppKit, SwiftUI, PDFKit, Vision Framework, CoreGraphics, UniformTypeIdentifiers  
**Inspiration:** Tangerine architecture (reverse-engineered via REA)

---

## 1. Executive Summary & Vision

FlipDoc is a native, ultra-lightweight macOS application designed for instant, zero-interruption document transformations. Instead of launching heavy desktop applications or uploading private documents to online converter websites, users drag any file across their screen, tap a keyboard modifier (`⇧ Shift`, `⌘ Command`, or `⌃ Control`), and drop the file onto an intuitive radial fan menu to immediately convert, extract, or action it.

Everything executes **100% locally on Apple Silicon**, ensuring complete privacy, zero latency, and no reliance on cloud services.

---

## 2. Core User Experience (The "Zero-Click" Interaction Model)

FlipDoc replicates the fluid, non-intrusive gesture model uncovered in Tangerine:

```
[User starts dragging file in Finder / Desktop]
              │
              ▼
    [User taps a modifier key]
    ├── ⇧ Shift   ──► Radial Fan: File Format Conversions (PDF, Excel, Word, Markdown, Images)
    ├── ⌘ Command ──► Radial Fan: Document & File Tools (Extract Tables, OCR, Compress, Split, Merge)
    └── ⌃ Control ──► Radial Fan: Quick Actions (Float Preview, AirDrop, Copy Path, Terminal)
              │
              ▼
[Radial fan menu appears centered at mouse cursor]
              │
              ▼
[User hovers over desired sector & releases mouse / drops file]
              │
              ▼
[Transformation executes locally; converted file saved next to original]
```

### Key Interaction Principles:
1. **Zero-Click Activation**: No opening menus, choosing files in dialog boxes, or browser tabs.
2. **Context-Aware Sectors**: The radial fan dynamically adapts its available sectors depending on the input file's UTType (e.g. PDF shows Tables/Excel/Markdown; Image shows WebP/PNG/OCR; Archive shows Extract/Compress).
3. **Menu Bar Agent (`LSUIElement = true`)**: FlipDoc lives unobtrusively in the menu bar with zero Dock clutter.

---

## 3. Transformation & Extraction Matrix

### 3.1. Document & PDF Transformations (FlipDoc Core)
| Input Format | Available Conversions | Engine / Framework |
|---|---|---|
| **PDF** | → Excel (`.xlsx`) *Extract Tables* | Native OpenXML Generator + PDFKit text bounds |
| **PDF** | → Markdown (`.md`) with layout & tables | PDFKit text layout analysis |
| **PDF** | → Images (`.png`, `.jpg` at 300 DPI) | PDFKit rendering + ImageIO |
| **PDF** | → Plain Text (`.txt`) | PDFKit string stream |
| **PDF** | → Compact / Compressed PDF | Quartz PDF filters |
| **PDF** | → Split / Merge Pages | PDFDocument page manipulation |

### 3.2. Image & OCR Capabilities
| Input Format | Available Conversions | Engine / Framework |
|---|---|---|
| **Images (PNG, JPG, HEIC, TIFF, WebP)** | → Formats (PNG, JPG, WebP, TIFF, PDF) | ImageIO, CoreGraphics |
| **Images / Scanned PDFs** | → Text / Markdown via **OCR** | Apple Vision Framework (`VNRecognizeTextRequest`) |
| **Images** | → Strip EXIF / Privacy Metadata | ImageIO metadata filtering |

### 3.3. File Tools & Quick Actions (`⌘` & `⌃`)
* **Float**: Pin a floating, translucent preview window of the file on screen (`FloatingFileWindowController`).
* **Copy Path**: Copy POSIX or file URL path to clipboard.
* **AirDrop**: Open native `NSSharingService` picker.
* **Open in Terminal**: Launch current directory in user's default shell.

---

## 4. Technical Architecture

```
FlipDoc/
├── App/
│   ├── FlipDocApp.swift                 # App lifecycle (NSApplicationDelegate, LSUIElement)
│   ├── MenuBarController.swift          # Status bar item & settings
│   └── AppState.swift                   # Global state, permissions, preferences
├── Overlay/
│   ├── GlobalDragMonitor.swift          # NSEvent global flagsChanged & drag tracking
│   ├── RadialOverlayWindow.swift        # Borderless, transparent floating NSPanel
│   ├── RadialFanView.swift              # SwiftUI Canvas / radial sector rendering
│   └── GestureEngine.swift              # Angle calculation, sector hit-testing & spring animations
├── Engines/
│   ├── TransformerProtocol.swift        # Unified protocol: transform(inputURL) -> Result<URL>
│   ├── PDFTableExtractor.swift          # Table detection & Excel (.xlsx) OpenXML builder
│   ├── PDFMarkdownConverter.swift       # Structured text & table extraction to Markdown
│   ├── PDFImageExporter.swift           # High-DPI page rendering to PNG/JPG
│   ├── ImageTransformer.swift           # Image format transcoding & metadata stripping
│   └── VisionOCREngine.swift            # Native Apple Vision text recognition
├── Actions/
│   ├── FloatingWindowController.swift   # Pinned floating file preview
│   └── SystemActionController.swift     # AirDrop, Terminal, Clipboard handlers
└── Common/
    ├── FileTypeClassifier.swift         # UTType matching & format availability graph
    └── SoundManager.swift               # Subtle haptic / audio feedback upon drop
```

---

## 5. Implementation Phases & Milestones

### Phase 1: Foundation & Swift Project Setup
* Clean repository, initialize Swift Package / macOS application structure.
* Build `FileTypeClassifier` and format graph (which formats accept what transformations).
* Setup `MenuBarController` for menu bar presence and quit/settings controls.

### Phase 2: Native Conversion Engines
* **Table to Excel (`.xlsx`) Engine**: Pure Swift OpenXML builder creating multi-sheet spreadsheets without external heavy dependencies.
* **PDF to Markdown & Image Engines**: High-fidelity PDF page rendering and text extraction via `PDFKit`.
* **Vision OCR Engine**: Extract text from scans/images using Apple's neural engine.

### Phase 3: Radial Fan UI & Global Event Tap
* Implement `RadialOverlayWindow` (`NSPanel` with `.nonactivatingPanel`, transparent background).
* Build `RadialFanView` in SwiftUI using `Path` arc maths and spring hover animations.
* Hook into `NSEvent.addGlobalMonitorForEvents` to detect cursor drag and `Shift` / `Cmd` / `Ctrl` toggles.

### Phase 4: Floating Windows & System Polish
* Add "Float" preview window for pinned reference documents.
* Add audio/haptic feedback on drop completion.
* Add Finder Quick Action integration (via macOS Services / Shortcuts).

---

## 6. Success Metrics
* **Zero Cloud Dependence**: 100% of operations run completely offline.
* **Latency**: Menu pops up in `< 16ms` (60fps); table conversions complete in `< 500ms` for standard documents.
* **Sandbox Compliance**: Operates safely using user-selected drag-and-drop security bookmarks.
