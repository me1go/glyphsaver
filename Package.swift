// swift-tools-version: 5.9
import PackageDescription

// SPM builds the core library, the dev preview app, and the test runner.
// The .saver bundle itself is assembled by the Makefile (swiftc + manual bundle),
// because building loadable bundles is outside SPM's product types.
let package = Package(
    name: "GlyphSaver",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GlyphSaverCore"),
        .target(name: "GlyphSaverKit", dependencies: ["GlyphSaverCore"]),
        .executableTarget(
            name: "GlyphSaverPreview",
            dependencies: ["GlyphSaverCore", "GlyphSaverKit"],
            path: "PreviewApp"
        ),
        .executableTarget(
            name: "GlyphSaverTests",
            dependencies: ["GlyphSaverCore"],
            path: "Tests"
        ),
    ]
)
