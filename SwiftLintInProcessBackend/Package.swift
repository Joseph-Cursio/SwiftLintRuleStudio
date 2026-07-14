// swift-tools-version: 6.2
import PackageDescription

// The in-process SwiftLint backend for the sandboxed (Mac App Store) app target.
// Kept as a SEPARATE package so SwiftLint's heavy transitive deps (swift-syntax,
// SourceKitten) stay entirely out of SwiftLintRuleStudioCore and the non-sandboxed
// Studio target — only the Explorer target links this.
let package = Package(
    name: "SwiftLintInProcessBackend",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SwiftLintInProcessBackend",
            targets: ["SwiftLintInProcessBackend"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftLintRuleStudioCore"),
        // Pinned to the exact revision the sandbox spike proved viable on
        // Xcode 26.6 / Swift 6.3. This is the "hard-wired version" the App Store
        // edition ships; bump it (and re-verify) on a deliberate SwiftLint update.
        .package(
            url: "https://github.com/realm/SwiftLint.git",
            revision: "e4d82f13dcd25583c33caec013b084376db5125e"
        )
    ],
    targets: [
        .target(
            name: "SwiftLintInProcessBackend",
            dependencies: [
                .product(name: "SwiftLintRuleStudioCore", package: "SwiftLintRuleStudioCore"),
                .product(name: "SwiftLintFramework", package: "SwiftLint")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftLintInProcessBackendTests",
            dependencies: ["SwiftLintInProcessBackend"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
