import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import FlipDocCore

enum TestFixtures {
    static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FlipDocTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeTestPNG(at url: URL, width: Int = 360, height: Int = 240, text: String? = nil) throws {
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
            throw FlipDocError("Failed creating test CGContext")
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let text = text {
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 38),
                    .foregroundColor: NSColor.black
                ]
            )
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 32, y: CGFloat(height / 2 - 14))
            CTLineDraw(line, ctx)
        } else {
            ctx.setFillColor(CGColor(red: 1.0, green: 0.322, blue: 0.0, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 60, y: 40, width: 120, height: 120))
        }

        guard let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FlipDocError("Failed finalizing test PNG")
        }
        let exifProps: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "FlipDoc Camera"
            ]
        ]
        CGImageDestinationAddImage(dest, cg, exifProps as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }
}

@Suite("Core Geometry, Routing & Output Naming")
struct CoreGeometryAndRoutingTests {

    @Test("PetalGeometry generates valid paths and exact hit-testing for 1...9 petals")
    func petalGeometryAndHitTesting() {
        for count in 1...9 {
            for idx in 0..<count {
                let path = PetalGeometry.makePetalPath(index: idx, count: count)
                #expect(!path.isEmpty)

                // Every petal's label centroid MUST hit-test strictly to its own index
                let centroid = PetalGeometry.labelPosition(index: idx, count: count)
                let hit = PetalGeometry.hitTest(dx: centroid.x, dy: centroid.y, count: count)
                #expect(hit == idx)
            }
        }

        // Inside donut hole and outside ring must return nil
        #expect(PetalGeometry.hitTest(dx: 0, dy: 0, count: 6) == nil)
        #expect(PetalGeometry.hitTest(dx: 20, dy: 10, count: 6) == nil)
        #expect(PetalGeometry.hitTest(dx: 160, dy: 0, count: 6) == nil)
    }

    @Test("FileCategory classifies files and filters out input's own extension")
    func fileCategoryOptionsFiltering() throws {
        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngURL = dir.appendingPathComponent("hero.png")
        try Data().write(to: pngURL)
        #expect(FileCategory.classify(url: pngURL) == .image)

        let pngConversions = FileCategory.options(for: [pngURL], mode: .conversions)
        #expect(!pngConversions.contains(where: { $0.targetExtension == "png" }))
        #expect(pngConversions.contains(where: { $0.targetExtension == "webp" }))
        #expect(pngConversions.contains(where: { $0.targetExtension == "jpg" }))
        #expect(pngConversions.contains(where: { $0.targetExtension == "pdf" }))

        // Multi-image tools must expose Collage + Combine PDF
        let secondJPG = dir.appendingPathComponent("two.jpg")
        try Data().write(to: secondJPG)
        let multiTools = FileCategory.options(for: [pngURL, secondJPG], mode: .tools)
        #expect(multiTools.contains(where: { $0.actionTag == "create_collage" }))
        #expect(multiTools.contains(where: { $0.actionTag == "to_pdf" }))

        // All 6 core file actions must appear in .actions mode
        let actions = FileCategory.options(for: [pngURL], mode: .actions)
        #expect(actions.count == 6)
        #expect(actions.map(\.actionTag) == ["float_file", "airdrop_file", "copy_file", "move_file", "copy_path", "open_terminal"])
    }

    @Test("OutputNaming never overwrites originals and appends collision counters cleanly")
    func outputNamingCollisionSafety() throws {
        let dir = try TestFixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let orig = dir.appendingPathComponent("report.pdf")
        try "v1".write(to: orig, atomically: true, encoding: .utf8)

        // Same extension as original must jump straight to `report 2.pdf`
        let sameExt = OutputNaming.uniqueFileURL(nextTo: orig, newExtension: "pdf")
        #expect(sameExt.lastPathComponent == "report 2.pdf")

        // Different extension uses `report.xlsx`, then `report 2.xlsx` once occupied
        let firstXlsx = OutputNaming.uniqueFileURL(nextTo: orig, newExtension: "xlsx")
        #expect(firstXlsx.lastPathComponent == "report.xlsx")
        try "sheet".write(to: firstXlsx, atomically: true, encoding: .utf8)

        let secondXlsx = OutputNaming.uniqueFileURL(nextTo: orig, newExtension: "xlsx")
        #expect(secondXlsx.lastPathComponent == "report 2.xlsx")

        // .tar.gz stem stripping
        let tgz = dir.appendingPathComponent("backup.tar.gz")
        #expect(OutputNaming.baseName(for: tgz) == "backup")
    }
}
