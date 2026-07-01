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
        // PBT adoption — supplies `Generator`/`Gen` for the `gen()` escape-hatch
        // extensions in PBTGenerators.swift, which unblock swift-infer verify on
        // the opaque `AnyCodable` (wraps `Any`) and external `URL` carriers.
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftLintRuleStudioCore",
            dependencies: [
                "Yams",
                .product(name: "LintStudioCore", package: "LintStudioUI"),
                .product(name: "PropertyBased", package: "swift-property-based")
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
                "SwiftLintRuleStudioCoreTestSupport"
            ],
            swiftSettings: swiftSettings
        )
    ]
)
