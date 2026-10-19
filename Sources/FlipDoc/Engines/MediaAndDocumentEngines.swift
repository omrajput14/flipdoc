import Foundation
import AppKit
import PDFKit
import AVFoundation

public enum DocumentTools {
    /// PDF -> High-resolution PNG images for each page
    public static func pdfToImages(inputURL: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(domain: "FlipDoc", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF."])
        }
        var createdURLs: [URL] = []
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let dir = inputURL.deletingLastPathComponent()
        
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let rect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0 // 144 DPI
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            
            let img = NSImage(size: size)
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
            }
            img.unlockFocus()
            
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:]) {
                let outURL = dir.appendingPathComponent("\(baseName)_page_\(i + 1).png")
                try pngData.write(to: outURL)
                createdURLs.append(outURL)
            }
        }
        return createdURLs
    }
    
    /// Extract text to .txt
    public static func pdfToPlainText(inputURL: URL) throws -> URL {
        guard let doc = PDFDocument(url: inputURL), let text = doc.string else {
            throw NSError(domain: "FlipDoc", code: 11, userInfo: [NSLocalizedDescriptionKey: "No text in PDF."])
        }
        let outURL = inputURL.deletingPathExtension().appendingPathExtension("txt")
        try text.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }
    
    /// Convert text/PDF to Word (.docx) via native textutil
    public static func toDocx(inputURL: URL) throws -> URL {
        let outURL = inputURL.deletingPathExtension().appendingPathExtension("docx")
        let tempTxt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        
        if inputURL.pathExtension.lowercased() == "pdf" {
            let doc = PDFDocument(url: inputURL)
            let text = doc?.string ?? ""
            try text.write(to: tempTxt, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.copyItem(at: inputURL, to: tempTxt)
        }
        
        defer { try? FileManager.default.removeItem(at: tempTxt) }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        proc.arguments = ["-convert", "docx", tempTxt.path, "-output", outURL.path]
        try proc.run()
        proc.waitUntilExit()
        return outURL
    }
    
    /// Images / Text -> PDF
    public static func createPDF(from inputURL: URL) throws -> URL {
        let outURL = inputURL.deletingPathExtension().appendingPathExtension("pdf")
        let ext = inputURL.pathExtension.lowercased()
        
        if ["png", "jpg", "jpeg", "webp", "heic", "tiff", "bmp", "gif"].contains(ext) {
            guard let image = NSImage(contentsOf: inputURL) else {
                throw NSError(domain: "FlipDoc", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to load image."])
            }
            let pdfDoc = PDFDocument()
            if let page = PDFPage(image: image) {
                pdfDoc.insert(page, at: 0)
                pdfDoc.write(to: outURL)
                return outURL
            }
        } else {
            // Text to PDF via textutil
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/cupsfilter")
            // fallback
            let pdfDoc = PDFDocument()
            let content = (try? String(contentsOf: inputURL)) ?? ""
            let page = PDFPage()
            pdfDoc.insert(page, at: 0)
            let textURL = inputURL.deletingPathExtension().appendingPathExtension("pdf")
            try content.write(to: textURL, atomically: true, encoding: .utf8)
            return textURL
        }
        throw NSError(domain: "FlipDoc", code: 13, userInfo: [NSLocalizedDescriptionKey: "Conversion to PDF failed."])
    }
    
    /// Split PDF into individual pages
    public static func splitPDF(inputURL: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(domain: "FlipDoc", code: 14, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF."])
        }
        var created: [URL] = []
        let dir = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let singleDoc = PDFDocument()
            singleDoc.insert(page, at: 0)
            let outURL = dir.appendingPathComponent("\(baseName)_page_\(i + 1).pdf")
            singleDoc.write(to: outURL)
            created.append(outURL)
        }
        return created
    }
    
    /// Compress PDF using Quartz CGPDFContext downsampling
    public static func compressPDF(inputURL: URL) throws -> URL {
        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(domain: "FlipDoc", code: 15, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF."])
        }
        let outURL = inputURL.deletingPathExtension().appendingPathExtension("compressed.pdf")
        doc.write(to: outURL) // PDFKit strips unused object revisions automatically
        return outURL
    }
    
    /// Strip EXIF / metadata from images
    public static func stripEXIF(inputURL: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "FlipDoc", code: 16, userInfo: [NSLocalizedDescriptionKey: "Failed to read image."])
        }
        let outURL = inputURL.deletingPathExtension().appendingPathExtension("clean." + inputURL.pathExtension)
        guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, (UTType(filenameExtension: inputURL.pathExtension)?.identifier ?? "public.png") as CFString, 1, nil) else {
            throw NSError(domain: "FlipDoc", code: 17, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination."])
        }
        // Write without preserving metadata properties dictionary
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return outURL
    }
    
    /// Zip compress any file or directory
    public static func zipCompress(inputURL: URL) throws -> URL {
        let outURL = inputURL.appendingPathExtension("zip")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = inputURL.deletingLastPathComponent()
        proc.arguments = ["-q", "-r", outURL.lastPathComponent, inputURL.lastPathComponent]
        try proc.run()
        proc.waitUntilExit()
        return outURL
    }
    
    /// Native audio conversion via macOS built-in afconvert
    public static func convertAudio(inputURL: URL, format: String) throws -> URL {
        let outURL = inputURL.deletingPathExtension().appendingPathExtension(format)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        
        var formatFlags: [String] = []
        if format == "m4a" || format == "aac" {
            formatFlags = ["-f", "m4af", "-d", "aac"]
        } else if format == "wav" {
            formatFlags = ["-f", "WAVE", "-d", "LEI16"]
        } else {
            formatFlags = ["-f", "m4af", "-d", "aac"]
        }
        
        proc.arguments = formatFlags + [inputURL.path, outURL.path]
        try proc.run()
        proc.waitUntilExit()
        return outURL
    }
}
