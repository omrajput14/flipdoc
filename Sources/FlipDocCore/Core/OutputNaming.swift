import Foundation

/// Collision-safe file and directory naming for FlipDoc's non-destructive local workflow.
/// Originals are NEVER overwritten; duplicates append ` 2`, ` 3`, etc.
public enum OutputNaming {
    /// Strips `.tar.gz`, `.tgz`, or standard single file extension cleanly.
    public static func baseName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") {
            return String(name.dropLast(7))
        } else if lower.hasSuffix(".tgz") {
            return String(name.dropLast(4))
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "Output" : stem
    }

    /// Generates a unique file URL beside `sourceURL` (e.g. `photo.png`, `photo 2.png` or `photo Compressed.jpg`).
    public static func uniqueFileURL(
        nextTo sourceURL: URL,
        suffix: String? = nil,
        newExtension: String
    ) -> URL {
        let dir = sourceURL.deletingLastPathComponent()
        let base = baseName(for: sourceURL)
        let cleanExt = newExtension.hasPrefix(".") ? String(newExtension.dropFirst()) : newExtension
        let stem = suffix.map { "\(base) \($0)" } ?? base

        let firstCandidate = cleanExt.isEmpty
            ? dir.appendingPathComponent(stem)
            : dir.appendingPathComponent("\(stem).\(cleanExt)")

        if !FileManager.default.fileExists(atPath: firstCandidate.path) && firstCandidate.standardizedFileURL != sourceURL.standardizedFileURL {
            return firstCandidate
        }

        var counter = 2
        while true {
            let candidateName = cleanExt.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(cleanExt)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) && candidate.standardizedFileURL != sourceURL.standardizedFileURL {
                return candidate
            }
            counter += 1
        }
    }

    /// Generates and creates a unique directory beside `sourceURL` (e.g. `notes Pages`, `notes Pages 2`).
    public static func uniqueDirectoryURL(
        nextTo sourceURL: URL,
        suffix: String
    ) throws -> URL {
        let dir = sourceURL.deletingLastPathComponent()
        let base = baseName(for: sourceURL)
        let stem = "\(base) \(suffix)"

        var candidate = dir.appendingPathComponent(stem, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(counter)", isDirectory: true)
            counter += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }
}

