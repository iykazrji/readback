// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Readback",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Readback", targets: ["Readback"]),
        .executable(name: "readback-cli", targets: ["readback-cli"]),
    ],
    targets: [
        // Pure logic with no UI: markdown cleanup, sentence chunks, HTTP parsing, config.
        .target(name: "ReadbackCore"),
        // The menu bar app and floating player.
        .executableTarget(name: "Readback", dependencies: ["ReadbackCore"]),
        // The `readback` command the tools' hooks run; bundled as Contents/Helpers/readback.
        .executableTarget(name: "readback-cli", dependencies: ["ReadbackCore"]),
        .testTarget(name: "ReadbackCoreTests", dependencies: ["ReadbackCore"]),
    ],
    swiftLanguageModes: [.v5]
)
