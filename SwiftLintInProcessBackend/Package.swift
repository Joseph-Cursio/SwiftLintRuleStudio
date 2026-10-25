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
        // Already in the graph through SwiftLint and Core; used directly to read
        // `.swiftlint.yml` the way SwiftLint does (see InProcessConfiguration).
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        // Also already in the graph through SwiftLint; used to match `excluded` the way
        // SwiftLint does when retracing its file walk (see SymlinkLoopCheck).
        .package(url: "https://github.com/ileitch/swift-filename-matcher", .upToNextMinor(from: "2.0.1")),
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
                // Only the seam, not all of Core: this target implements the protocol and
                // wants none of the app's MainActor isolation default.
                .product(name: "SwiftLintCLISeam", package: "SwiftLintRuleStudioCore"),
                .product(name: "SwiftLintFramework", package: "SwiftLint"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "FilenameMatcher", package: "swift-filename-matcher")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftLintInProcessBackendTests",
            dependencies: [
                "SwiftLintInProcessBackend",
                .product(name: "SwiftLintRuleStudioCore", package: "SwiftLintRuleStudioCore"),
                // The rule-list agreement tests read SwiftLint's own resolved configuration.
                .product(name: "SwiftLintFramework", package: "SwiftLint")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
