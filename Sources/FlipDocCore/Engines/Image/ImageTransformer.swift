import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import WebKit

public enum ImageTransformer {

    /// Converts a single image to the target format (`jpg`, `png`, `webp`, `heic`, `avif`, `tiff`, `bmp`).
    public static func convert(inputURL: URL, toFormat format: String, quality: Double = 0.92) async throws -> URL {
        let lower = format.lowercased()
        if lower == "webp" {
            return try await convertToWebP(inputURL: inputURL, quality: quality)
        }
        if lower == "pdf" {
            return try combineImagesToPDF(inputURLs: [inputURL])
        }

        let cgImage = try loadOrientedCGImage(from: inputURL)
        let (utTypeIdentifier, ext) = utTypeAndExtension(for: lower)
        let outputURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: ext)

        try writeCGImage(cgImage, to: outputURL, utTypeIdentifier: utTypeIdentifier, quality: quality, stripMetadata: false)
        return outputURL
    }

    /// Combines one or multiple images into a crisp multi-page PDF beside the first image.
    public static func combineImagesToPDF(inputURLs: [URL]) throws -> URL {
        guard let first = inputURLs.first else {
            throw FlipDocError("No images selected.")
        }
        let pdfDoc = PDFDocument()
        var pageIndex = 0

        for url in inputURLs {
            let cgImage = try loadOrientedCGImage(from: url)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            if let page = PDFPage(image: nsImage) {
                pdfDoc.insert(page, at: pageIndex)
                pageIndex += 1
            }
        }

        guard pageIndex > 0 else {
            throw FlipDocError("Could not render images into PDF pages.")
        }

        let suffix = inputURLs.count > 1 ? "Combined" : nil
        let outURL = OutputNaming.uniqueFileURL(nextTo: first, suffix: suffix, newExtension: "pdf")
        guard pdfDoc.write(to: outURL) else {
            throw FlipDocError("Failed to save PDF to disk.")
        }
        return outURL
    }

    /// Compresses an image with target quality (`0.1...1.0`) and optional maximum pixel dimension.
    public static func compress(
        inputURL: URL,
        quality: Double,
        maxDimension: Int? = nil
    ) async throws -> URL {
        var cgImage = try loadOrientedCGImage(from: inputURL)
        if let maxDim = maxDimension, maxDim > 0 {
            let currentMax = max(cgImage.width, cgImage.height)
            if currentMax > maxDim {
                let scale = Double(maxDim) / Double(currentMax)
                let newW = max(1, Int((Double(cgImage.width) * scale).rounded()))
                let newH = max(1, Int((Double(cgImage.height) * scale).rounded()))
                cgImage = try resizeCGImage(cgImage, width: newW, height: newH)
            }
        }

        let ext = inputURL.pathExtension.lowercased()
        // Note: PNG is lossless so compressing a large PNG without alpha uses high-efficiency JPG or scaled PNG
        let hasAlpha = imageHasAlpha(cgImage)
        let targetExt: String
        if ext == "png" && !hasAlpha && quality < 0.9 {
            targetExt = "jpg"
        } else if ["jpg", "jpeg", "heic", "avif", "webp", "png"].contains(ext) {
            targetExt = ext == "jpeg" ? "jpg" : ext
        } else {
            targetExt = "jpg"
        }

        if targetExt == "webp" {
            let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: tempPNG) }
            try writeCGImage(cgImage, to: tempPNG, utTypeIdentifier: UTType.png.identifier, quality: 1.0, stripMetadata: true)
            let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Compressed", newExtension: "webp")
            try await encodeWebPToDestination(sourceURL: tempPNG, outputURL: outURL, quality: quality)
            return outURL
        }

        let (utID, cleanExt) = utTypeAndExtension(for: targetExt)
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Compressed", newExtension: cleanExt)
        try writeCGImage(cgImage, to: outURL, utTypeIdentifier: utID, quality: quality, stripMetadata: true)
        return outURL
    }

    /// Resizes an image and optionally adds rounded corners & background padding.
    public static func resizeAndFrame(
        inputURL: URL,
        targetWidth: Int,
        targetHeight: Int,
        cornerRadius: CGFloat = 0,
        padding: CGFloat = 0,
        backgroundColor: CGColor? = nil
    ) throws -> URL {
        let source = try loadOrientedCGImage(from: inputURL)
        let canvasW = max(1, targetWidth + Int(padding * 2))
        let canvasH = max(1, targetHeight + Int(padding * 2))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FlipDocError("Failed to create graphics canvas.")
        }

        ctx.interpolationQuality = .high
        if let bg = backgroundColor {
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        }

        let drawRect = CGRect(x: padding, y: padding, width: CGFloat(targetWidth), height: CGFloat(targetHeight))
        if cornerRadius > 0 {
            ctx.saveGState()
            let path = CGPath(roundedRect: drawRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(source, in: drawRect)
            ctx.restoreGState()
        } else {
            ctx.draw(source, in: drawRect)
        }

        guard let result = ctx.makeImage() else {
            throw FlipDocError("Failed to render resized image.")
        }

        let needsPNG = cornerRadius > 0 && backgroundColor == nil
        let origExt = inputURL.pathExtension.lowercased()
        let outExt = needsPNG ? "png" : (["jpg", "jpeg", "png", "heic", "tiff"].contains(origExt) ? (origExt == "jpeg" ? "jpg" : origExt) : "png")
        let (utID, cleanExt) = utTypeAndExtension(for: outExt)
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "Resized", newExtension: cleanExt)
        try writeCGImage(result, to: outURL, utTypeIdentifier: utID, quality: 0.94, stripMetadata: false)
        return outURL
    }

    /// Reads human-readable metadata tags for the Metadata Inspector window.
    public static func inspectMetadata(url: URL) -> [(key: String, value: String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return []
        }
        var pairs: [(String, String)] = []
        if let w = props[kCGImagePropertyPixelWidth as String], let h = props[kCGImagePropertyPixelHeight as String] {
            pairs.append(("Dimensions", "\(w) × \(h) px"))
        }
        if let colorModel = props[kCGImagePropertyColorModel as String] as? String {
            pairs.append(("Color Space", colorModel))
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake as String] { pairs.append(("Camera Make", "\(make)")) }
            if let model = tiff[kCGImagePropertyTIFFModel as String] { pairs.append(("Camera Model", "\(model)")) }
            if let software = tiff[kCGImagePropertyTIFFSoftware as String] { pairs.append(("Software", "\(software)")) }
            if let dt = tiff[kCGImagePropertyTIFFDateTime as String] { pairs.append(("Timestamp", "\(dt)")) }
        }
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let lens = exif[kCGImagePropertyExifLensModel as String] { pairs.append(("Lens", "\(lens)")) }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any])?.first { pairs.append(("ISO", "\(iso)")) }
            if let fn = exif[kCGImagePropertyExifFNumber as String] { pairs.append(("Aperture", "f/\(fn)")) }
        }
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = gps[kCGImagePropertyGPSLatitude as String],
           let lon = gps[kCGImagePropertyGPSLongitude as String] {
            pairs.append(("GPS Location", "\(lat), \(lon)"))
        }
        return pairs
    }

    /// Strips all EXIF, GPS, TIFF, and IPTC metadata by re-encoding raw pixel buffer.
    public static func stripMetadata(inputURL: URL) throws -> URL {
        let cgImage = try loadOrientedCGImage(from: inputURL)
        let ext = inputURL.pathExtension.lowercased()
        let safeExt = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "avif"].contains(ext) ? (ext == "jpeg" ? "jpg" : ext) : "png"
        let (utID, cleanExt) = utTypeAndExtension(for: safeExt)
        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, suffix: "No Metadata", newExtension: cleanExt)
        try writeCGImage(cgImage, to: outURL, utTypeIdentifier: utID, quality: 0.95, stripMetadata: true)
        return outURL
    }

    /// Builds a clean high-resolution photo collage from 2+ images.
    public static func createCollage(inputURLs: [URL]) throws -> URL {
        guard let first = inputURLs.first else {
            throw FlipDocError("Select at least one image for a collage.")
        }
        let images = try inputURLs.map { try loadOrientedCGImage(from: $0) }
        let canvasW = 1920
        let canvasH = 1440
        let gap: CGFloat = 24
        let outerPad: CGFloat = 32

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FlipDocError("Failed to allocate collage canvas.")
        }

        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        let innerW = CGFloat(canvasW) - outerPad * 2
        let innerH = CGFloat(canvasH) - outerPad * 2

        var rects: [CGRect] = []
        if images.count == 1 {
            rects = [CGRect(x: outerPad, y: outerPad, width: innerW, height: innerH)]
        } else if images.count == 2 {
            let w = (innerW - gap) / 2
            rects = [
                CGRect(x: outerPad, y: outerPad, width: w, height: innerH),
                CGRect(x: outerPad + w + gap, y: outerPad, width: w, height: innerH)
            ]
        } else if images.count == 3 {
            // Featured 3-up layout: 1 tall left + 2 stacked right
            let w = (innerW - gap) / 2
            let h = (innerH - gap) / 2
            rects = [
                CGRect(x: outerPad, y: outerPad, width: w, height: innerH),
                CGRect(x: outerPad + w + gap, y: outerPad + h + gap, width: w, height: h),
                CGRect(x: outerPad + w + gap, y: outerPad, width: w, height: h)
            ]
        } else {
            let cols = Int(ceil(sqrt(Double(images.count))))
            let rows = Int(ceil(Double(images.count) / Double(cols)))
            let cellW = (innerW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (innerH - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for idx in 0..<images.count {
                let r = idx / cols
                let c = idx % cols
                let flippedRow = (rows - 1) - r
                rects.append(CGRect(
                    x: outerPad + CGFloat(c) * (cellW + gap),
                    y: outerPad + CGFloat(flippedRow) * (cellH + gap),
                    width: cellW,
                    height: cellH
                ))
            }
        }

        for (img, rect) in zip(images, rects) {
            drawAspectFill(img, in: rect, cornerRadius: 18, ctx: ctx)
        }

        guard let composed = ctx.makeImage() else {
            throw FlipDocError("Failed to render collage.")
        }
        let outURL = OutputNaming.uniqueFileURL(nextTo: first, suffix: "Collage", newExtension: "png")
        try writeCGImage(composed, to: outURL, utTypeIdentifier: UTType.png.identifier, quality: 1.0, stripMetadata: true)
        return outURL
    }

    // MARK: - Helpers

    public static func loadOrientedCGImage(from url: URL) throws -> CGImage {
        if url.pathExtension.lowercased() == "svg",
           let nsImg = NSImage(contentsOf: url) {
            let targetSize = NSSize(
                width: max(512, nsImg.size.width * 2),
                height: max(512, nsImg.size.height * 2)
            )
            var rect = NSRect(origin: .zero, size: targetSize)
            if let cg = nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return cg
            }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FlipDocError("Failed to read image file \(url.lastPathComponent).")
        }
        let maxPixel = 8192
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            return thumb
        }
        if let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return raw
        }
        throw FlipDocError("Unsupported or corrupted image data in \(url.lastPathComponent).")
    }

    private static func writeCGImage(
        _ cgImage: CGImage,
        to outputURL: URL,
        utTypeIdentifier: String,
        quality: Double,
        stripMetadata: Bool
    ) throws {
        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, utTypeIdentifier as CFString, 1, nil) else {
            throw FlipDocError("Format \(outputURL.pathExtension.uppercased()) is not supported by ImageIO on this Mac.")
        }
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.05, min(1.0, quality)),
            kCGImageDestinationEmbedThumbnail: false
        ]
        if stripMetadata {
            props[kCGImageMetadataShouldExcludeXMP] = true
        }
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FlipDocError("Failed writing image to \(outputURL.lastPathComponent).")
        }
    }

    private static func resizeCGImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FlipDocError("Could not allocate resize buffer.")
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else {
            throw FlipDocError("Failed resizing image.")
        }
        return out
    }

    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, cornerRadius: CGFloat, ctx: CGContext) {
        ctx.saveGState()
        let clipPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(clipPath)
        ctx.clip()

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scale = max(rect.width / imgW, rect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(
            x: rect.midX - drawW / 2.0,
            y: rect.midY - drawH / 2.0,
            width: drawW,
            height: drawH
        )
        ctx.draw(image, in: drawRect)
        ctx.restoreGState()
    }

    private static func imageHasAlpha(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    private static func utTypeAndExtension(for format: String) -> (String, String) {
        switch format.lowercased() {
        case "jpg", "jpeg": return (UTType.jpeg.identifier, "jpg")
        case "png": return (UTType.png.identifier, "png")
        case "heic", "heif": return (UTType.heic.identifier, "heic")
        case "avif": return ("public.avif", "avif")
        case "tiff", "tif": return (UTType.tiff.identifier, "tiff")
        case "bmp": return (UTType.bmp.identifier, "bmp")
        case "gif": return (UTType.gif.identifier, "gif")
        case "ico": return (UTType.ico.identifier, "ico")
        case "icns": return (UTType.icns.identifier, "icns")
        default: return (UTType.png.identifier, "png")
        }
    }

    // MARK: - Local WebP Encoder (CLI cwebp/ffmpeg fast-path + pure Apple WebKit <canvas> fallback)

    private static func convertToWebP(inputURL: URL, quality: Double) async throws -> URL {
        let cgImage = try loadOrientedCGImage(from: inputURL)
        let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tempPNG) }
        try writeCGImage(cgImage, to: tempPNG, utTypeIdentifier: UTType.png.identifier, quality: 1.0, stripMetadata: false)

        let outURL = OutputNaming.uniqueFileURL(nextTo: inputURL, newExtension: "webp")
        try await encodeWebPToDestination(sourceURL: tempPNG, outputURL: outURL, quality: quality)
        return outURL
    }

    private static func encodeWebPToDestination(sourceURL: URL, outputURL: URL, quality: Double) async throws {
        let qInt = max(10, min(100, Int((quality * 100).rounded())))

        // 1. Check cwebp if present
        let cwebpCandidates = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
        if let cwebp = cwebpCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cwebp)
            proc.arguments = ["-q", "\(qInt)", sourceURL.path, "-o", outputURL.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                return
            }
        }

        // 2. Check ffmpeg if present
        let ffmpegCandidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            NSHomeDirectory() + "/.local/bin/ffmpeg"
        ]
        if let ffmpeg = ffmpegCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ffmpeg)
            proc.arguments = ["-y", "-i", sourceURL.path, "-quality", "\(qInt)", outputURL.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                return
            }
        }

        // 3. 100% Native Apple WebKit <canvas>.toDataURL("image/webp") fallback (works on every Mac offline!)
        let pngData = try Data(contentsOf: sourceURL)
        let webpData = try await WebKitCanvasWebPEncoder.encode(pngData: pngData, quality: quality)
        try webpData.write(to: outputURL, options: .atomic)
    }
}

@MainActor
private final class WebKitCanvasWebPEncoder: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?
    private let pngBase64: String
    private let quality: Double

    private init(pngData: Data, quality: Double) {
        self.pngBase64 = pngData.base64EncodedString()
        self.quality = max(0.1, min(1.0, quality))
    }

    static func encode(pngData: Data, quality: Double) async throws -> Data {
        let encoder = WebKitCanvasWebPEncoder(pngData: pngData, quality: quality)
        return try await encoder.run()
    }

    private func run() async throws -> Data {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 16, height: 16), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            wv.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        const img = new Image();
        await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = () => reject(new Error("Image decode failed"));
            img.src = "data:image/png;base64,\(pngBase64)";
        });
        const canvas = document.createElement("canvas");
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0);
        return canvas.toDataURL("image/webp", \(quality));
        """

        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self = self, let cont = self.continuation else { return }
            self.continuation = nil
            self.webView = nil

            switch result {
            case .success(let value):
                guard let dataURL = value as? String,
                      let commaIdx = dataURL.firstIndex(of: ","),
                      dataURL.hasPrefix("data:image/webp"),
                      let decoded = Data(base64Encoded: String(dataURL[dataURL.index(after: commaIdx)...])) else {
                    cont.resume(throwing: FlipDocError("WebP encoding returned unexpected payload."))
                    return
                }
                cont.resume(returning: decoded)
            case .failure(let error):
                cont.resume(throwing: error)
            }
        }
    }
}

public struct FlipDocError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

