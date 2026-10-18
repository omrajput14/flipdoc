// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlipDoc",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FlipDoc",
            targets: ["FlipDoc"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FlipDoc",
            dependencies: [],
            path: "Sources/FlipDoc",
            resources: []
        ),
        .testTarget(
            name: "FlipDocTests",
            dependencies: ["FlipDoc"],
            path: "Tests/FlipDocTests"
        )
    ]
)
