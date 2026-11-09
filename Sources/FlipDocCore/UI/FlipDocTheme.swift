import SwiftUI
import AppKit

/// Signature FlipDoc Studio design system tokens.
public enum FlipDocTheme {
    /// Signature vibrant FlipDoc orange (`#FF5200`) used on radial petal highlights & primary CTAs.
    public static let orange = Color(red: 1.0, green: 0.322, blue: 0.0)
    /// Warm secondary ember accent (`#F35B28`) used for badges, keycaps, and typography highlights.
    public static let warmOrange = Color(red: 0.953, green: 0.357, blue: 0.157)
    /// Soft tinted orange surface (`#FFF0E4`) for held shortcut keys and subtle highlights.
    public static let softOrangeSurface = Color(red: 1.0, green: 0.941, blue: 0.894)
    /// Warm studio canvas (`#F4F4F4` light / `#161718` dark).
    public static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.095, blue: 0.10)
            : Color(red: 0.957, green: 0.957, blue: 0.953)
    }
    /// Crisp card surface (`#FFFFFF` light / `#202224` dark).
    public static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.14, blue: 0.15)
            : Color.white
    }
    /// Subtle hairline border (`#E6E8E5` light / `#FFFFFF18` dark).
    public static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.895, green: 0.905, blue: 0.89)
    }

    public static let nsOrange = NSColor(srgbRed: 1.0, green: 0.322, blue: 0.0, alpha: 1.0)

    /// Loads the official MELD Ribbon Logo from the app bundle (`Contents/Resources/MELDLogo.png`) or workspace `Assets/MELDLogo.png`.
    public static func meldLogoImage() -> NSImage? {
        if let bundled = Bundle.main.url(forResource: "MELDLogo", withExtension: "png"),
           let img = NSImage(contentsOf: bundled) {
            return img
        }
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/MELDLogo.png"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Assets/MELDLogo.png")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }
}

public struct MeldBrandMarkView: View {
    public let size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        if let nsImg = FlipDocTheme.meldLogoImage() {
            Image(nsImage: nsImg)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .shadow(color: FlipDocTheme.orange.opacity(0.28), radius: 7, x: 0, y: 3)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [FlipDocTheme.orange, FlipDocTheme.warmOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
