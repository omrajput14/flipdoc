import Foundation
import UniformTypeIdentifiers

public enum ModifierMode: String, CaseIterable, Sendable {
    case conversions = "⇧ Shift"
    case tools = "⌘ Command"
    case actions = "⌃ Control"
    
    public var label: String {
        switch self {
        case .conversions: return "Convert Formats"
        case .tools: return "File & Doc Tools"
        case .actions: return "Quick Actions"
        }
    }
}

public struct FanOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let systemImage: String
    public let targetExtension: String?
    public let actionTag: String
    
    public init(id: String, label: String, systemImage: String, targetExtension: String? = nil, actionTag: String) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.targetExtension = targetExtension
        self.actionTag = actionTag
    }
}

public enum FileCategory: String, Sendable {
    case pdf
    case image
    case audio
    case video
    case document
    case spreadsheet
    case archive
    case unknown
    
    public static func classify(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["png", "jpg", "jpeg", "webp", "heic", "tiff", "bmp", "gif"].contains(ext) { return .image }
        if ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff"].contains(ext) { return .audio }
        if ["mp4", "mov", "mkv", "webm", "avi"].contains(ext) { return .video }
        if ["docx", "doc", "pages", "txt", "md", "rtf"].contains(ext) { return .document }
        if ["xlsx", "xls", "numbers", "csv", "tsv"].contains(ext) { return .spreadsheet }
        if ["zip", "tar", "gz", "rar", "7z"].contains(ext) { return .archive }
        return .unknown
    }
    
    public func options(for mode: ModifierMode) -> [FanOption] {
        switch mode {
        case .conversions:
            switch self {
            case .pdf:
                return [
                    FanOption(id: "pdf_to_xlsx", label: "Excel Tables", systemImage: "tablecells", targetExtension: "xlsx", actionTag: "extract_tables"),
                    FanOption(id: "pdf_to_md", label: "Markdown", systemImage: "text.document", targetExtension: "md", actionTag: "to_markdown"),
                    FanOption(id: "pdf_to_png", label: "Images (PNG)", systemImage: "photo.stack", targetExtension: "png", actionTag: "to_images"),
                    FanOption(id: "pdf_to_txt", label: "Plain Text", systemImage: "doc.text", targetExtension: "txt", actionTag: "to_text"),
                    FanOption(id: "pdf_to_docx", label: "Word (DOCX)", systemImage: "doc.richtext", targetExtension: "docx", actionTag: "to_docx")
                ]
            case .image:
                return [
                    FanOption(id: "img_to_png", label: "PNG", systemImage: "photo", targetExtension: "png", actionTag: "to_png"),
                    FanOption(id: "img_to_jpg", label: "JPG", systemImage: "photo.fill", targetExtension: "jpg", actionTag: "to_jpg"),
                    FanOption(id: "img_to_webp", label: "WebP", systemImage: "sparkles", targetExtension: "webp", actionTag: "to_webp"),
                    FanOption(id: "img_to_pdf", label: "PDF Document", systemImage: "doc.fill", targetExtension: "pdf", actionTag: "to_pdf"),
                    FanOption(id: "img_ocr_txt", label: "OCR to Text", systemImage: "text.viewfinder", targetExtension: "txt", actionTag: "ocr_text")
                ]
            case .audio:
                return [
                    FanOption(id: "audio_to_mp3", label: "MP3", systemImage: "waveform", targetExtension: "mp3", actionTag: "to_mp3"),
                    FanOption(id: "audio_to_m4a", label: "M4A", systemImage: "waveform.path", targetExtension: "m4a", actionTag: "to_m4a"),
                    FanOption(id: "audio_to_wav", label: "WAV", systemImage: "music.note", targetExtension: "wav", actionTag: "to_wav")
                ]
            case .video:
                return [
                    FanOption(id: "vid_to_mp4", label: "MP4", systemImage: "film", targetExtension: "mp4", actionTag: "to_mp4"),
                    FanOption(id: "vid_to_gif", label: "GIF Animation", systemImage: "play.square.stack", targetExtension: "gif", actionTag: "to_gif"),
                    FanOption(id: "vid_to_mp3", label: "Extract MP3 Audio", systemImage: "speaker.wave.2", targetExtension: "mp3", actionTag: "extract_audio")
                ]
            case .spreadsheet, .document, .archive, .unknown:
                return [
                    FanOption(id: "doc_to_pdf", label: "PDF Export", systemImage: "doc.fill", targetExtension: "pdf", actionTag: "to_pdf"),
                    FanOption(id: "doc_to_txt", label: "Plain Text", systemImage: "doc.text", targetExtension: "txt", actionTag: "to_text")
                ]
            }
            
        case .tools:
            switch self {
            case .pdf:
                return [
                    FanOption(id: "tool_ocr", label: "OCR Scan", systemImage: "text.viewfinder", actionTag: "ocr_full"),
                    FanOption(id: "tool_compress", label: "Compress PDF", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "compress_pdf"),
                    FanOption(id: "tool_split", label: "Split Pages", systemImage: "square.split.2x1", actionTag: "split_pages")
                ]
            case .image:
                return [
                    FanOption(id: "tool_ocr_img", label: "Live OCR Extract", systemImage: "text.viewfinder", actionTag: "ocr_full"),
                    FanOption(id: "tool_strip_exif", label: "Strip EXIF / Privacy", systemImage: "shield.slash", actionTag: "strip_exif"),
                    FanOption(id: "tool_compress_img", label: "Compress", systemImage: "arrow.down.right.and.arrow.up.left", actionTag: "compress_image")
                ]
            default:
                return [
                    FanOption(id: "tool_compress_zip", label: "Zip Archive", systemImage: "archivebox", actionTag: "zip_compress")
                ]
            }
            
        case .actions:
            return [
                FanOption(id: "act_float", label: "Float On Screen", systemImage: "pip", actionTag: "float_file"),
                FanOption(id: "act_airdrop", label: "AirDrop", systemImage: "airdrop", actionTag: "airdrop_file"),
                FanOption(id: "act_copy_path", label: "Copy Path", systemImage: "link", actionTag: "copy_path"),
                FanOption(id: "act_terminal", label: "Open in Terminal", systemImage: "terminal", actionTag: "open_terminal")
            ]
        }
    }
}
