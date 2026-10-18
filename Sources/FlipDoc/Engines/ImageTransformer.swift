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
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FlipDoc", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to write transformed image."])
        }
        
        return outputURL
    }
}
