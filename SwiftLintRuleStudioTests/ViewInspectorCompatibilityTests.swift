//
//  ViewInspectorCompatibilityTests.swift
//  SwiftLintRuleStudioTests
//
//  Preflight for the ViewInspector assumptions that fail catastrophically
//  rather than gracefully.
//

import SwiftUI
import Testing
import ViewInspector

/// ViewInspector reflects into private SwiftUI layout, so an OS update can break
/// it while the public API is unchanged. Two such breaks bit this project on
/// macOS 27 beta:
///
/// - `GeometryProxy` has no public initializer, so ViewInspector fabricates one
///   from a zeroed allocation. Until nalexn/ViewInspector#421 that allocation was
///   a fixed-size `unsafeBitCast` recognizing only 48 and 52 bytes; macOS 27
///   reports 76 and the unguarded fallback trapped.
/// - `AccessibilityProperties` replaced its named members with a generic
///   `storage` array, so every `accessibilityLabel()` lookup threw.
///
/// The first is the dangerous one: a trap is not a test failure, it kills the
/// whole test process, so every suite scheduled alongside it is reported failed —
/// ~115 of them here, a different set each run. The real cause is invisible in
/// that output, because the reported crash site is the Swift stdlib's
/// `unsafeBitCast` rather than ViewInspector.
///
/// These tests exercise the two capabilities directly, on the smallest possible
/// views, so a future regression surfaces as a named failure here instead of as
/// unexplained collateral across the target.
@Suite("ViewInspector compatibility")
@MainActor
struct ViewInspectorCompatibilityTests {

    private struct GeometryProbe: View {
        var body: some View {
            GeometryReader { proxy in
                Rectangle()
                    .frame(width: max(0, proxy.size.width))
                    .accessibilityIdentifier("probe")
            }
        }
    }

    private struct AccessibilityProbe: View {
        var body: some View {
            Button("Probe") {}
                .accessibilityLabel("Probe label")
        }
    }

    @Test("ViewInspector can traverse into a GeometryReader on this OS")
    func geometryReaderTraversalWorks() throws {
        // Reaching the child forces ViewInspector to fabricate the GeometryProxy,
        // which is the step that trapped. RuleAuditRow, RuleAuditRow+ExpandedDetail
        // and ConfigHealthScoreView all render a GeometryReader, so their suites
        // depend on this working.
        let identifier = try GeometryProbe().inspect()
            .geometryReader()
            .shape()
            .accessibilityIdentifier()

        #expect(
            identifier == "probe",
            """
            ViewInspector could not traverse into a GeometryReader on this OS.

            MemoryLayout<GeometryProxy>.size is \(MemoryLayout<GeometryProxy>.size) \
            bytes. If ViewInspector has regressed to a fixed-size fabrication, this \
            traversal traps rather than fails, killing the test process — treat any \
            mass failure of unrelated suites as collateral. withKnownIssue cannot \
            help, because a fatalError is not a recorded issue.
            """
        )
    }

    @Test("ViewInspector can read accessibility modifiers on this OS")
    func accessibilityIntrospectionWorks() throws {
        let label = try AccessibilityProbe().inspect().button().accessibilityLabel().string()

        #expect(
            label == "Probe label",
            """
            ViewInspector could not read an accessibility modifier on this OS.

            This fails on the simplest possible view, so it is a library/OS layout \
            mismatch rather than anything wrong with the views under test. The \
            XCUITest target still reads the real accessibility tree.
            """
        )
    }
}
