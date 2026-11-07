// swift-tools-version: 6.0
import PackageDescription
import Foundation

let cltTestingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
var testSwiftSettings: [SwiftSetting] = []
if FileManager.default.fileExists(atPath: cltTestingPluginPath) {
    testSwiftSettings.append(.unsafeFlags(["-plugin-path", cltTestingPluginPath]))
}

let package = Package(
    name: "FlipDoc",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FlipDocCore",
            targets: ["FlipDocCore"]
        ),
        .executable(
            name: "FlipDoc",
            targets: ["FlipDoc"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FlipDocCore",
            dependencies: [],
            path: "Sources/FlipDocCore"
        ),
        .executableTarget(
            name: "FlipDoc",
            dependencies: ["FlipDocCore"],
            path: "Sources/FlipDoc"
        ),
        .testTarget(
            name: "FlipDocTests",
            dependencies: ["FlipDocCore"],
            path: "Tests/FlipDocTests",
            swiftSettings: testSwiftSettings
        )
    ]
)
