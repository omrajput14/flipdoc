import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageTransformer {
    public static func convert(inputURL: URL, toUTType: UTType) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "FlipDoc", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read image source."])
        }
        
        let fileExt: String
        switch toUTType {
        case .png: fileExt = "png"
        case .jpeg: fileExt = "jpg"
        case .webP: fileExt = "webp"
        case .tiff: fileExt = "tiff"
        case .pdf: fileExt = "pdf"
        default: fileExt = toUTType.preferredFilenameExtension ?? "out"
        }
        
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension(fileExt)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, toUTType.identifier as CFString, 1, nil) else {
            throw NSError(domain: "FlipDoc", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination."])
        }
        
        // Maximum quality: lossless for PNG/TIFF, highest quality for JPEG/WebP
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0,  // 1.0 = maximum (no quality loss)
            kCGImageDestinationEmbedThumbnail: false
        ]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FlipDoc", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to write transformed image."])
        }
        
        return outputURL
    }
}
