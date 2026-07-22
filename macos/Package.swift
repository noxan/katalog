// swift-tools-version:5.9
import PackageDescription

// Run ../build-core.sh first — it produces dist/Katalog.xcframework and
// Generated/katalog.swift, both consumed below. Open this Package.swift in
// Xcode (or `swift run Katalog`) to launch the app.
let package = Package(
    name: "Katalog",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(name: "katalogFFI", path: "../dist/Katalog.xcframework"),
        .target(
            name: "KatalogCore",
            dependencies: ["katalogFFI"],
            path: "Generated",
            sources: ["katalog.swift"]
        ),
        .executableTarget(
            name: "Katalog",
            dependencies: ["KatalogCore"],
            path: "Sources/Katalog"
        ),
    ]
)
