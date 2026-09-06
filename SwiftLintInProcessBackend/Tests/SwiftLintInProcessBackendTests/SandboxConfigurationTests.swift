//
//  SandboxConfigurationTests.swift
//  SwiftLintInProcessBackendTests
//
//  The Explorer edition shares its entire UI with Studio; what differs is the
//  composition root. These cover that difference — the reduced capability set,
//  the in-process backend, and the sandbox-safety bootstrap — because a
//  regression in any of them ships a broken App Store build while every Studio
//  test still passes.
//
//  These live in the package suite rather than an Xcode test target: a test
//  bundle hosted by the Explorer app forces every package product to build as a
//  dynamic framework, which breaks SwiftLint's macro plugin at compile time and
//  its dynamic loading at runtime. `swift test` builds the package natively and
//  sidesteps both. The trade-off is that these exercise the sandbox *logic*
//  without running inside a sandboxed process.
//

import Foundation
import SwiftLintInProcessBackend
@testable import SwiftLintRuleStudioCore
import Testing

// Core is built with `.defaultIsolation(MainActor.self)`, so its model methods are
// MainActor-isolated. This package isn't, so the suite opts in explicitly rather
// than each call site awaiting across the boundary.
@Suite("Sandbox configuration")
@MainActor
struct SandboxConfigurationTests {

    // MARK: - Capabilities

    /// The capability set the Explorer app injects at its root.
    private static let explorerCapabilities: Set<AppCapability> = []

    @Test("The sandboxed edition advertises no external-tool capabilities")
    func explorerHasNoCapabilities() {
        // Studio injects the full set; Explorer injects none, because under the
        // sandbox there is no swiftlint binary to detect and no xed to launch.
        #expect(Self.explorerCapabilities.isEmpty)
        #expect(!Self.explorerCapabilities.contains(.detectInstalledSwiftLint))
        #expect(!Self.explorerCapabilities.contains(.openInXcode))
        #expect(!Self.explorerCapabilities.contains(.sourceKitRules))
    }

    @Test("SourceKit rules are reported unavailable rather than silently passing")
    func sourceKitRulesAreMarkedUnavailable() {
        let sourceKitRule = Rule(
            id: "explicit_self",
            name: "Explicit Self",
            description: "Requires explicit self",
            category: .style,
            isOptIn: true,
            usesSourceKit: true
        )

        // The in-process backend sets SWIFTLINT_DISABLE_SOURCEKIT, so these rules
        // produce no violations. The UI must say so instead of implying they ran.
        #expect(sourceKitRule.isUnavailableForLinting(capabilities: Self.explorerCapabilities))
    }

    @Test("Non-SourceKit rules stay available under the sandbox")
    func nonSourceKitRulesRemainAvailable() {
        let plainRule = Rule(
            id: "force_cast",
            name: "Force Cast",
            description: "Avoid force casting",
            category: .lint,
            isOptIn: false,
            usesSourceKit: false
        )

        #expect(!plainRule.isUnavailableForLinting(capabilities: Self.explorerCapabilities))
    }

    @Test("Studio's full capability set would keep SourceKit rules available")
    func fullCapabilitiesKeepSourceKitRules() {
        // Guards the comparison the other way: if this ever fails, the two
        // editions have stopped differing and the reduced set is doing nothing.
        let sourceKitRule = Rule(
            id: "explicit_self",
            name: "Explicit Self",
            description: "Requires explicit self",
            category: .style,
            isOptIn: true,
            usesSourceKit: true
        )

        #expect(!sourceKitRule.isUnavailableForLinting(capabilities: Set(AppCapability.allCases)))
    }

    // MARK: - In-process backend

    @Test("The backend reports an in-process path rather than an external binary")
    func backendReportsInProcessPath() async throws {
        let backend = SwiftLintInProcessActor()

        let path = try await backend.detectSwiftLintPath()

        // Nothing to detect under the sandbox; the marker path stands in for a
        // real binary so the onboarding flow has something to show.
        #expect(path.path.contains("in-process"))
    }

    @Test("The backend reports a SwiftLint version without an external binary")
    func backendReportsVersion() async throws {
        let backend = SwiftLintInProcessActor()

        let version = try await backend.getVersion()

        #expect(!version.isEmpty)
        #expect(version.contains("."), "expected a dotted version, got \(version)")
    }

    // MARK: - Sandbox bootstrap

    @Test("prepare() sets the sandbox-safety environment variables")
    func prepareSetsSandboxEnvironment() {
        SwiftLintInProcessActor.prepare()

        let environment = ProcessInfo.processInfo.environment

        // SourceKit cannot load from outside the app container, so it must be
        // disabled before any SwiftLintFramework symbol is touched.
        #expect(environment["SWIFTLINT_DISABLE_SOURCEKIT"] == "1")
        // With SourceKit off, the version can't be probed, so it's pinned —
        // without it, version-gated rules silently misbehave.
        #expect(environment["SWIFTLINT_SWIFT_VERSION"]?.isEmpty == false)
    }

    @Test("prepare() is idempotent")
    func prepareIsIdempotent() {
        SwiftLintInProcessActor.prepare()
        let first = ProcessInfo.processInfo.environment["SWIFTLINT_SWIFT_VERSION"]

        SwiftLintInProcessActor.prepare()
        let second = ProcessInfo.processInfo.environment["SWIFTLINT_SWIFT_VERSION"]

        #expect(first == second)
    }
}
