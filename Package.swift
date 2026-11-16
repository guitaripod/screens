// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "screens",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "screens",
            linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("AppKit")]
        ),
    ]
)
