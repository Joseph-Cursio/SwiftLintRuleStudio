//
//  ViewInspectorCompatibilityTests.swift
//  SwiftLintRuleStudioTests
//
//  Preflight for the one ViewInspector assumption that fails catastrophically
//  rather than gracefully.
//

import SwiftUI
import Testing

/// SwiftUI gives `GeometryProxy` no public initializer, so ViewInspector
/// fabricates one by `unsafeBitCast`-ing a zeroed struct of a hardcoded size —
/// see `Sources/ViewInspector/SwiftUI/GeometryReader.swift`. It recognizes 52
/// and 48 bytes; for any other size it bitcasts the 48-byte allocator anyway,
/// with no guard, and traps.
///
/// A trap is not a test failure. It kills the whole test process, so every suite
/// scheduled alongside it is reported as failed — ~115 of them here, a different
/// set each run because the scheduling is nondeterministic. The real cause is
/// invisible in that output: the reported crash site is the Swift stdlib's
/// `unsafeBitCast`, not ViewInspector.
///
/// This test converts that into one named failure carrying the actual number.
@Suite("ViewInspector compatibility")
struct ViewInspectorCompatibilityTests {

    /// Sizes ViewInspector 0.10.3 knows how to fabricate. Update this to match
    /// `GeometryProxy.init()` in whatever version the project pins.
    private static let supportedGeometryProxySizes = [48, 52]

    @Test("ViewInspector can fabricate a GeometryProxy on this OS")
    func geometryProxyLayoutIsSupported() {
        let size = MemoryLayout<GeometryProxy>.size

        #expect(
            Self.supportedGeometryProxySizes.contains(size),
            """
            ViewInspector cannot fabricate a GeometryProxy on this OS.

            MemoryLayout<GeometryProxy>.size is \(size) bytes; ViewInspector \
            0.10.3 handles only \(Self.supportedGeometryProxySizes). Its \
            unguarded fallback will unsafeBitCast a 48-byte allocator into a \
            \(size)-byte type and trap.

            Consequence: any ViewInspector traversal reaching a GeometryReader \
            kills the test process. In this project that is RuleAuditRow.swift, \
            RuleAuditRow+ExpandedDetail.swift and ConfigHealthScoreView.swift, \
            so RuleAuditViewTests, RuleAuditRowAccessibilityTests, \
            RuleAuditRowExpandedDetailTests and ConfigHealthScoreViewTests \
            cannot run. Treat any mass failure of unrelated suites as collateral.

            Measured 76 bytes on macOS 27.0 beta (26A5388g). Adding an \
            Allocator76 to ViewInspector locally cleared the crash and let all \
            21 tests in those suites execute, so a size-matched allocator is \
            the fix. Note withKnownIssue cannot help: this is a fatalError trap, \
            not a recorded issue.
            """
        )
    }
}
