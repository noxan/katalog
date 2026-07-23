// swift-tools-version:6.2
import PackageDescription

// Run ../build-core.sh first — it produces dist/Katalog.xcframework and
// Generated/katalog.swift, both consumed below. Open this Package.swift in
// Xcode (or `swift run Katalog`) to launch the app.
let package = Package(
    name: "Katalog",
    platforms: [.macOS(.v26)],  // ToolbarSpacer + Liquid Glass toolbar
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
    ],
    // Stay on Swift 5 semantics — no strict-concurrency churn for this MVP.
    swiftLanguageModes: [.v5]
)
