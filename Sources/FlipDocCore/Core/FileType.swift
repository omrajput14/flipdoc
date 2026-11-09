import Foundation
import UniformTypeIdentifiers

public enum ModifierMode: String, CaseIterable, Sendable {
    case conversions = "conversions"
    case tools = "tools"
    case actions = "actions"

    public var keySymbol: String {
        switch self {
        case .conversions: return "⇧"
        case .tools: return "⌘"
        case .actions: return "⌃"
        }
    }

    public var shortTitle: String {
        switch self {
        case .conversions: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    public var wheelTitle: String {
        switch self {
        case .conversions: return "CONVERT"
        case .tools: return "TOOLS"
        case .actions: return "ACTIONS"
        }
    }
}

public struct FanOption: Identifiable, Hashable, Sendable {
    public let id: String
    /// Compact uppercase wheel label (e.g. `PNG`, `XLSX`, `COMPRESS`, `FLOAT`).
    public let wheelTitle: String
    /// Human-readable full title (e.g. `Convert to PNG`, `Extract Excel Tables`, `Compress File`).
    public let label: String
    public let systemImage: String
    public let targetExtension: String?
    public let actionTag: String
    /// Whether an icon should be displayed above the petal text (true for Tools & Actions, false for crisp format names).
    public let showsPetalIcon: Bool
    /// Whether selecting this option opens an interactive tool options sheet rather than running silently.
    public let opensToolSheet: Bool

    public init(
        id: String,
        wheelTitle: String,
        label: String,
        systemImage: String,
        targetExtension: String? = nil,
        actionTag: String,
        showsPetalIcon: Bool = false,
        opensToolSheet: Bool = false
    ) {
        self.id = id
        self.wheelTitle = wheelTitle
        self.label = label
        self.systemImage = systemImage
        self.targetExtension = targetExtension
        self.actionTag = actionTag
        self.showsPetalIcon = showsPetalIcon
        self.opensToolSheet = opensToolSheet
    }
}

public enum FileCategory: String, Sendable {
    case pdf
    case image
    case video
    case audio
    case document
    case spreadsheet
    case subtitle
    case archive
    case folder
    case unknown

    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif", "avif", "ico", "icns", "svg"
    ]
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "flac", "aiff", "aif", "aac", "caf", "ogg", "opus"
    ]
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi"
    ]
    public static let documentExtensions: Set<String> = [
        "docx", "doc", "rtf", "rtfd", "txt", "md", "markdown", "html", "htm"
    ]
    public static let spreadsheetExtensions: Set<String> = [
        "xlsx", "xls", "csv", "tsv"
    ]
    public static let subtitleExtensions: Set<String> = [
        "srt", "vtt"
    ]
    public static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz"
    ]

    public static func classify(url: URL) -> FileCategory {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if url.pathExtension.lowercased() == "rtfd" {
                return .document
            }
            return .folder
        }
        let lowerName = url.lastPathComponent.lowercased()
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") {
            return .archive
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        if documentExtensions.contains(ext) { return .document }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if subtitleExtensions.contains(ext) { return .subtitle }
        if archiveExtensions.contains(ext) { return .archive }
        return .unknown
    }

    /// Context-aware radial wheel options for 1 or multiple dragged/selected URLs.
    public static func options(for urls: [URL], mode: ModifierMode) -> [FanOption] {
        guard let first = urls.first else { return [] }
        let categories = urls.map { classify(url: $0) }
        let primary = categories[0]
        let allSameCategory = Set(categories).count == 1
        let isMultiple = urls.count > 1

        // Canonicalize input extension (e.g. jpeg -> jpg, tif -> tiff, tar.gz -> gz)
        let singleInputExt: String? = {
            guard !isMultiple else { return nil }
            let lower = first.lastPathComponent.lowercased()
            if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return "gz" }
            let raw = first.pathExtension.lowercased()
            switch raw {
            case "jpeg": return "jpg"
            case "tif": return "tiff"
            case "htm": return "html"
            case "markdown": return "md"
            case "aif": return "aiff"
            default: return raw
            }
        }()

        switch mode {
        case .actions:
            // All 6 core file actions
            return [
                FanOption(id: "act_float", wheelTitle: "FLOAT", label: "Pin to Float Shelf", systemImage: "pin.fill", actionTag: "float_file", showsPetalIcon: true),
                FanOption(id: "act_airdrop", wheelTitle: "AIRDROP", label: "Share via AirDrop", systemImage: "airplayaudio", actionTag: "airdrop_file", showsPetalIcon: true),
                FanOption(id: "act_copy", wheelTitle: "COPY", label: "Copy to Clipboard", systemImage: "doc.on.doc", actionTag: "copy_file", showsPetalIcon: true),
                FanOption(id: "act_move", wheelTitle: "MOVE", label: "Move to Folder…", systemImage: "folder", actionTag: "move_file", showsPetalIcon: true),
                FanOption(id: "act_copy_path", wheelTitle: "COPY PATH", label: "Copy File Path", systemImage: "doc.text", actionTag: "copy_path", showsPetalIcon: true),
                FanOption(id: "act_terminal", wheelTitle: "TERMINAL", label: "Open in Terminal", systemImage: "terminal", actionTag: "open_terminal", showsPetalIcon: true)
            ]

        case .conversions:
            if !allSameCategory {
                // Mixed selection: offer universal Archive exports
                return [
                    FanOption(id: "mix_zip", wheelTitle: "ZIP", label: "Pack into ZIP", systemImage: "archivebox", targetExtension: "zip", actionTag: "to_zip"),
                    FanOption(id: "mix_tar_gz", wheelTitle: "GZIP", label: "Pack into TAR.GZ", systemImage: "archivebox.fill", targetExtension: "gz", actionTag: "to_targz")
                ]
            }

            var list: [FanOption]
            switch primary {
            case .image:
                list = [
                    FanOption(id: "img_jpg", wheelTitle: "JPG", label: "Convert to JPG", systemImage: "photo", targetExtension: "jpg", actionTag: "to_jpg"),
                    FanOption(id: "img_png", wheelTitle: "PNG", label: "Convert to PNG", systemImage: "photo.fill", targetExtension: "png", actionTag: "to_png"),
                    FanOption(id: "img_webp", wheelTitle: "WEBP", label: "Convert to WebP", systemImage: "sparkles", targetExtension: "webp", actionTag: "to_webp"),
                    FanOption(id: "img_heic", wheelTitle: "HEIC", label: "Convert to HEIC", systemImage: "camera", targetExtension: "heic", actionTag: "to_heic"),
                    FanOption(id: "img_avif", wheelTitle: "AVIF", label: "Convert to AVIF", systemImage: "wand.and.stars", targetExtension: "avif", actionTag: "to_avif"),
                    FanOption(id: "img_tiff", wheelTitle: "TIFF", label: "Convert to TIFF", systemImage: "doc.richtext", targetExtension: "tiff", actionTag: "to_tiff"),
                    FanOption(id: "img_bmp", wheelTitle: "BMP", label: "Convert to BMP", systemImage: "square.grid.3x3", targetExtension: "bmp", actionTag: "to_bmp"),
                    FanOption(id: "img_pdf", wheelTitle: "PDF", label: isMultiple ? "Combine into PDF" : "Convert to PDF", systemImage: "doc.fill", targetExtension: "pdf", actionTag: "to_pdf")
                ]
            case .pdf:
                list = [
                    FanOption(id: "pdf_xlsx", wheelTitle: "XLSX", label: "Extract Tables to Excel", systemImage: "tablecells", targetExtension: "xlsx", actionTag: "extract_tables"),
                    FanOption(id: "pdf_docx", wheelTitle: "DOCX", label: "Convert to Word", systemImage: "doc.richtext", targetExtension: "docx", actionTag: "to_docx"),
                    FanOption(id: "pdf_md", wheelTitle: "MD", label: "Convert to Markdown", systemImage: "text.document", targetExtension: "md", actionTag: "to_markdown"),
                    FanOption(id: "pdf_png", wheelTitle: "PNG", label: "Export Pages as PNG", systemImage: "photo.stack", targetExtension: "png", actionTag: "pdf_to_png"),
                    FanOption(id: "pdf_jpg", wheelTitle: "JPG", label: "Export Pages as JPG", systemImage: "photo.on.rectangle", targetExtension: "jpg", actionTag: "pdf_to_jpg"),
                    FanOption(id: "pdf_txt", wheelTitle: "TXT", label: "Extract Plain Text", systemImage: "doc.text", targetExtension: "txt", actionTag: "to_text"),
                    FanOption(id: "pdf_html", wheelTitle: "HTML", label: "Convert to HTML", systemImage: "globe", targetExtension: "html", actionTag: "to_html")
                ]
            case .video:
                list = [
                    FanOption(id: "vid_mp4", wheelTitle: "MP4", label: "Convert to MP4", systemImage: "film", targetExtension: "mp4", actionTag: "to_mp4"),
                    FanOption(id: "vid_mov", wheelTitle: "MOV", label: "Convert to MOV", systemImage: "video", targetExtension: "mov", actionTag: "to_mov"),
                    FanOption(id: "vid_gif", wheelTitle: "GIF", label: "Convert to Animated GIF", systemImage: "play.square.stack", targetExtension: "gif", actionTag: "to_gif"),
                    FanOption(id: "vid_m4a", wheelTitle: "M4A", label: "Extract M4A Audio", systemImage: "waveform", targetExtension: "m4a", actionTag: "extract_m4a"),
                    FanOption(id: "vid_wav", wheelTitle: "WAV", label: "Extract WAV Audio", systemImage: "speaker.wave.2", targetExtension: "wav", actionTag: "extract_wav")
                ]
            case .audio:
                list = [
                    FanOption(id: "aud_m4a", wheelTitle: "M4A", label: "Convert to M4A (AAC)", systemImage: "waveform", targetExtension: "m4a", actionTag: "to_m4a"),
                    FanOption(id: "aud_wav", wheelTitle: "WAV", label: "Convert to WAV", systemImage: "waveform.path", targetExtension: "wav", actionTag: "to_wav"),
                    FanOption(id: "aud_aiff", wheelTitle: "AIFF", label: "Convert to AIFF", systemImage: "music.note", targetExtension: "aiff", actionTag: "to_aiff"),
                    FanOption(id: "aud_flac", wheelTitle: "FLAC", label: "Convert to FLAC", systemImage: "hifispeaker", targetExtension: "flac", actionTag: "to_flac")
                ]
            case .spreadsheet:
                list = [
                    FanOption(id: "xls_pdf", wheelTitle: "PDF", label: "Export Vector PDF", systemImage: "doc.fill", targetExtension: "pdf", actionTag: "to_pdf"),
                    FanOption(id: "xls_xlsx", wheelTitle: "XLSX", label: "Convert to Excel", systemImage: "tablecells", targetExtension: "xlsx", actionTag: "sheet_to_xlsx"),
                    FanOption(id: "xls_csv", wheelTitle: "CSV", label: "Convert to CSV", systemImage: "tablecells.badge.ellipsis", targetExtension: "csv", actionTag: "sheet_to_csv"),
                    FanOption(id: "xls_tsv", wheelTitle: "TSV", label: "Convert to TSV", systemImage: "list.bullet.rectangle", targetExtension: "tsv", actionTag: "sheet_to_tsv"),
                    FanOption(id: "xls_md", wheelTitle: "MD", label: "Convert to Markdown Table", systemImage: "text.document", targetExtension: "md", actionTag: "sheet_to_md")
                ]
            case .document:
                list = [
                    FanOption(id: "doc_pdf", wheelTitle: "PDF", label: "Export to PDF", systemImage: "doc.fill", targetExtension: "pdf", actionTag: "to_pdf"),
                    FanOption(id: "doc_docx", wheelTitle: "DOCX", label: "Convert to Word", systemImage: "doc.richtext", targetExtension: "docx", actionTag: "to_docx"),
                    FanOption(id: "doc_rtf", wheelTitle: "RTF", label: "Convert to Rich Text", systemImage: "textformat", targetExtension: "rtf", actionTag: "to_rtf"),
                    FanOption(id: "doc_html", wheelTitle: "HTML", label: "Convert to HTML", systemImage: "globe", targetExtension: "html", actionTag: "to_html"),
                    FanOption(id: "doc_md", wheelTitle: "MD", label: "Convert to Markdown", systemImage: "text.document", targetExtension: "md", actionTag: "doc_to_md"),
                    FanOption(id: "doc_txt", wheelTitle: "TXT", label: "Convert to Plain Text", systemImage: "doc.text", targetExtension: "txt", actionTag: "doc_to_txt")
                ]
            case .subtitle:
                list = [
                    FanOption(id: "sub_srt", wheelTitle: "SRT", label: "Convert to SRT", systemImage: "captions.bubble", targetExtension: "srt", actionTag: "sub_to_srt"),
                    FanOption(id: "sub_vtt", wheelTitle: "VTT", label: "Convert to WebVTT", systemImage: "captions.bubble.fill", targetExtension: "vtt", actionTag: "sub_to_vtt"),
                    FanOption(id: "sub_txt", wheelTitle: "TXT", label: "Extract Transcript", systemImage: "doc.text", targetExtension: "txt", actionTag: "sub_to_txt")
                ]
            case .archive, .folder:
                list = [
                    FanOption(id: "arc_zip", wheelTitle: "ZIP", label: "Convert to ZIP", systemImage: "archivebox", targetExtension: "zip", actionTag: "to_zip"),
                    FanOption(id: "arc_tar", wheelTitle: "TAR", label: "Convert to TAR", systemImage: "shippingbox", targetExtension: "tar", actionTag: "to_tar"),
                    FanOption(id: "arc_gz", wheelTitle: "GZIP", label: "Convert to TAR.GZ", systemImage: "archivebox.fill", targetExtension: "gz", actionTag: "to_targz")
                ]
            case .unknown:
                list = [
                    FanOption(id: "unk_zip", wheelTitle: "ZIP", label: "Compress to ZIP", systemImage: "archivebox", targetExtension: "zip", actionTag: "to_zip")
                ]
            }

            if let ext = singleInputExt {
                list.removeAll { $0.targetExtension == ext }
            }
            return list

        case .tools:
            if !allSameCategory {
                return [
                    FanOption(id: "tool_zip_mix", wheelTitle: "ARCHIVE", label: "Pack Selection to ZIP", systemImage: "archivebox", actionTag: "to_zip", showsPetalIcon: true)
                ]
            }

            switch primary {
            case .image:
                var tools: [FanOption] = [
                    FanOption(id: "tool_img_rembg", wheelTitle: "REMOVE BG", label: "Remove Background", systemImage: "person.crop.rectangle", actionTag: "remove_bg", showsPetalIcon: true),
                    FanOption(id: "tool_img_compress", wheelTitle: "COMPRESS", label: "Compress Image", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "tool_compress", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_img_resize", wheelTitle: "RESIZE", label: "Resize & Frame Image", systemImage: "crop", actionTag: "tool_resize_image", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_img_ocr", wheelTitle: "OCR", label: "Extract Text (OCR)", systemImage: "text.viewfinder", actionTag: "ocr_full", showsPetalIcon: true),
                    FanOption(id: "tool_img_qr", wheelTitle: "SCAN QR", label: "Scan QR / Barcode", systemImage: "qrcode.viewfinder", actionTag: "scan_qr", showsPetalIcon: true),
                    FanOption(id: "tool_img_redact", wheelTitle: "REDACT", label: "Redact Sensitive Info", systemImage: "eye.slash.fill", actionTag: "tool_redact", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_img_meta", wheelTitle: "METADATA", label: "Inspect / Strip EXIF", systemImage: "tag.slash", actionTag: "tool_metadata", showsPetalIcon: true, opensToolSheet: true)
                ]
                if isMultiple {
                    tools.append(FanOption(id: "tool_img_pdf", wheelTitle: "CREATE PDF", label: "Combine Images into PDF", systemImage: "doc.badge.plus", actionTag: "to_pdf", showsPetalIcon: true))
                    tools.append(FanOption(id: "tool_img_collage", wheelTitle: "COLLAGE", label: "Create Photo Collage", systemImage: "rectangle.3.group", actionTag: "create_collage", showsPetalIcon: true))
                }
                return tools

            case .pdf:
                var tools: [FanOption] = [
                    FanOption(id: "tool_pdf_compress", wheelTitle: "COMPRESS", label: "Compress PDF", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "tool_compress", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_pdf_handout", wheelTitle: "HANDOUT", label: "Create 3-Up Study Handout", systemImage: "list.bullet.rectangle.portrait", actionTag: "pdf_handout", showsPetalIcon: true),
                    FanOption(id: "tool_pdf_lock", wheelTitle: "LOCK / STAMP", label: "Password Lock & Watermark PDF", systemImage: "lock.doc.fill", actionTag: "tool_protect_pdf", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_pdf_redact", wheelTitle: "REDACT", label: "Redact Sensitive Info", systemImage: "eye.slash.fill", actionTag: "tool_redact", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_pdf_split", wheelTitle: "SPLIT", label: "Split PDF Pages", systemImage: "rectangle.split.2x1", actionTag: "split_pages", showsPetalIcon: true),
                    FanOption(id: "tool_pdf_organize", wheelTitle: isMultiple ? "MERGE PDF" : "ORGANIZE", label: isMultiple ? "Merge PDFs" : "Organize / Merge PDF", systemImage: isMultiple ? "doc.on.doc" : "square.grid.2x2", actionTag: "tool_organize_pdf", showsPetalIcon: true, opensToolSheet: true),
                    FanOption(id: "tool_pdf_ocr", wheelTitle: "OCR", label: "Scanned PDF OCR", systemImage: "text.viewfinder", actionTag: "ocr_full", showsPetalIcon: true)
                ]
                if isMultiple {
                    tools.insert(FanOption(id: "tool_pdf_quick_merge", wheelTitle: "QUICK MERGE", label: "Instant Merge PDFs", systemImage: "arrow.triangle.merge", actionTag: "quick_merge_pdf", showsPetalIcon: true), at: 0)
                }
                return tools

            case .video:
                return [
                    FanOption(id: "tool_vid_compress", wheelTitle: "COMPRESS", label: "Compress Video", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "compress_video", showsPetalIcon: true),
                    FanOption(id: "tool_vid_mute", wheelTitle: "MUTE", label: "Remove Audio Track", systemImage: "speaker.slash.fill", actionTag: "mute_video", showsPetalIcon: true),
                    FanOption(id: "tool_vid_speed", wheelTitle: "SPEED 2X", label: "Speed Up Video (2x)", systemImage: "gauge.with.dots.needle.67percent", actionTag: "video_speed_2x", showsPetalIcon: true),
                    FanOption(id: "tool_vid_snap", wheelTitle: "SNAPSHOTS", label: "Save Video Snapshots", systemImage: "camera", actionTag: "video_snapshots", showsPetalIcon: true),
                    FanOption(id: "tool_vid_gif", wheelTitle: "MAKE GIF", label: "Create GIF Preview", systemImage: "play.square.stack", actionTag: "to_gif", showsPetalIcon: true)
                ]

            case .audio:
                return [
                    FanOption(id: "tool_aud_compress", wheelTitle: "COMPRESS", label: "Compress Audio (AAC)", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "to_m4a", showsPetalIcon: true),
                    FanOption(id: "tool_aud_vis", wheelTitle: "VISUALIZE", label: "Render Waveform PNG", systemImage: "waveform.badge.plus", actionTag: "audio_visualize", showsPetalIcon: true),
                    FanOption(id: "tool_aud_mono", wheelTitle: "CHANNELS", label: "Convert to Mono", systemImage: "hifispeaker", actionTag: "audio_mono", showsPetalIcon: true),
                    FanOption(id: "tool_aud_zip", wheelTitle: "ARCHIVE", label: "Pack into ZIP", systemImage: "archivebox", actionTag: "to_zip", showsPetalIcon: true)
                ]

            case .archive:
                return [
                    FanOption(id: "tool_arc_extract", wheelTitle: "EXTRACT", label: "Extract Archive", systemImage: "archivebox.fill", actionTag: "extract_archive", showsPetalIcon: true)
                ]

            default:
                return [
                    FanOption(id: "tool_def_zip", wheelTitle: "COMPRESS", label: "Create ZIP Archive", systemImage: "archivebox", actionTag: "to_zip", showsPetalIcon: true)
                ]
            }
        }
    }

    public var iconName: String {
        switch self {
        case .pdf: return "doc.richtext.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .document: return "doc.text.fill"
        case .spreadsheet: return "tablecells.fill"
        case .subtitle: return "captions.bubble.fill"
        case .archive: return "archivebox.fill"
        case .folder: return "folder.fill"
        case .unknown: return "doc.fill"
        }
    }
}

