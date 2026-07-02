// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftLintRuleStudioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SwiftLintRuleStudioCore",
            targets: ["SwiftLintRuleStudioCore"]
        ),
        .library(
            name: "SwiftLintRuleStudioCoreTestSupport",
            targets: ["SwiftLintRuleStudioCoreTestSupport"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        .package(url: "https://github.com/Joseph-Cursio/LintStudioUI.git", from: "1.4.0"),
        // Test-only: property-law checking for the model value types. Wired into
        // the test target ONLY — the app links the SwiftLintRuleStudioCore product,
        // which must stay free of PropertyBased/Testing (putting this on the library
        // target is what broke the app build in 404e6fd; reverted in 1cc635c).
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "SwiftLintRuleStudioCore",
            dependencies: [
                "Yams",
                .product(name: "LintStudioCore", package: "LintStudioUI")
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SwiftLintRuleStudioCoreTestSupport",
            dependencies: ["SwiftLintRuleStudioCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SwiftLintRuleStudioCoreTests",
            dependencies: [
                "SwiftLintRuleStudioCore",
                "SwiftLintRuleStudioCoreTestSupport",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
            ],
            swiftSettings: swiftSettings
        )
    ]
)
