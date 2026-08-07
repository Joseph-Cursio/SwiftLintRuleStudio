//
//  RuleAuditRowExpandedDetailTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the expandable per-rule detail panel: the file breakdown bars,
//  the top-five cut-off, and the example violation.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

// Every test that inspects `expandedDetail` is disabled on macOS 27 beta (build
// 26A5388g). SwiftUI gives `GeometryProxy` no public initializer, so ViewInspector
// 0.10.3 fabricates one by `unsafeBitCast`-ing a fixed-size zeroed struct; it
// knows 48 and 52 bytes, this OS reports 76, and the unguarded fallback traps
// with "Can't unsafeBitCast between types of different sizes".
//
// A trap is not a test failure — it kills the test process. Left enabled, these
// crashloop the whole target: the run restarts repeatedly, unrelated suites are
// reported failed, and the set differs run to run. `withKnownIssue` cannot help,
// because this is a fatalError rather than a recorded issue. See
// ViewInspectorCompatibilityTests.swift for the preflight that names the size.
//
// `RuleAuditRow` renders a GeometryReader, so any traversal of it traps. The five
// `fileBarWidth` tests below stay enabled: they call the static function directly
// and never inspect a view. Re-enable the rest when upstream ships the fix
// (nalexn/ViewInspector PR #421, unmerged as of 2026-08-07).
@MainActor
@Suite("RuleAuditRow expanded detail")
struct RuleAuditRowExpandedDetailTests {

    // MARK: - Fixtures

    private static func makeRule(
        _ identifier: String = "force_cast",
        supportsAutocorrection: Bool = false
    ) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc for \(identifier)",
            category: .lint,
            isOptIn: false,
            severity: .warning,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: supportsAutocorrection
        )
    }

    /// One violation per entry in `linesPerFile`, so the breakdown can be given
    /// an exact shape.
    private static func makeViolations(
        _ linesPerFile: [(file: String, count: Int)],
        severity: Severity = .warning,
        message: String = "Something is wrong"
    ) -> [Violation] {
        linesPerFile.flatMap { entry in
            (1...entry.count).map { line in
                Violation(
                    ruleID: "force_cast",
                    filePath: entry.file,
                    line: line,
                    severity: severity,
                    message: message
                )
            }
        }
    }

    private static func makeRow(
        violations: [Violation],
        supportsAutocorrection: Bool = false
    ) -> RuleAuditRow {
        let impact = RuleImpactResult(
            ruleId: "force_cast",
            violationCount: violations.count,
            violations: violations,
            affectedFiles: Set(violations.map(\.filePath)),
            simulationDuration: 0.1
        )
        let entry = RuleAuditEntry(
            rule: makeRule(supportsAutocorrection: supportsAutocorrection),
            impactResult: impact,
            isCurrentlyEnabled: false
        )
        return RuleAuditRow(
            entry: entry,
            isExpanded: true,
            isSelected: false,
            totalSwiftFiles: 20,
            maxViolationCount: 50,
            onToggleExpand: {},
            onToggleSelect: {},
            onEnable: {}
        )
    }

    private static func detailContains(_ row: RuleAuditRow, text: String) -> Bool {
        (try? row.expandedDetail.inspect().find(text: text)) != nil
    }

    // MARK: - fileBarWidth

    @Test("The worst file fills the whole width")
    func barFillsWidthForWorstFile() {
        let width = RuleAuditRow.fileBarWidth(count: 10, maxCount: 10, in: 80)

        #expect(width == 80)
    }

    @Test("A bar is scaled in proportion to the worst file")
    func barScalesProportionally() {
        let width = RuleAuditRow.fileBarWidth(count: 5, maxCount: 10, in: 80)

        #expect(width == 40)
    }

    @Test("A tiny share is floored so the bar stays visible")
    func barIsFlooredAtTwoPoints() {
        // 1/1000 of 80pt is 0.08pt, which would render as nothing.
        let width = RuleAuditRow.fileBarWidth(count: 1, maxCount: 1_000, in: 80)

        #expect(width == 2)
    }

    @Test("A zero maximum yields no bar rather than dividing by zero")
    func barGuardsAgainstZeroMaximum() {
        #expect(RuleAuditRow.fileBarWidth(count: 0, maxCount: 0, in: 80) == 0)
        #expect(RuleAuditRow.fileBarWidth(count: 5, maxCount: 0, in: 80) == 0)
    }

    @Test("A zero-width container yields the floored bar, never a negative")
    func barHandlesZeroWidthContainer() {
        let width = RuleAuditRow.fileBarWidth(count: 5, maxCount: 10, in: 0)

        #expect(width == 2)
    }

    // MARK: - File breakdown

    @Test("The panel shows both section headings",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func showsSectionHeadings() {
        let row = Self.makeRow(violations: Self.makeViolations([("A.swift", 2)]))

        #expect(Self.detailContains(row, text: "File Breakdown"))
        #expect(Self.detailContains(row, text: "Example Violation"))
    }

    @Test("Each affected file is listed with its violation count",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func listsFilesWithCounts() {
        let row = Self.makeRow(
            violations: Self.makeViolations([("A.swift", 3), ("B.swift", 1)])
        )

        #expect(Self.detailContains(row, text: "A.swift"))
        #expect(Self.detailContains(row, text: "B.swift"))
        #expect(Self.detailContains(row, text: "3"))
    }

    @Test("Only the five worst files are listed, with the rest summarised",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func truncatesToTopFiveFiles() {
        // Seven files, descending so the cut-off is unambiguous.
        let row = Self.makeRow(
            violations: Self.makeViolations([
                ("One.swift", 7), ("Two.swift", 6), ("Three.swift", 5),
                ("Four.swift", 4), ("Five.swift", 3), ("Six.swift", 2),
                ("Seven.swift", 1)
            ])
        )

        #expect(Self.detailContains(row, text: "One.swift"))
        #expect(Self.detailContains(row, text: "Five.swift"))
        #expect(!Self.detailContains(row, text: "Six.swift"), "the sixth file must be cut")
        #expect(!Self.detailContains(row, text: "Seven.swift"))
        #expect(Self.detailContains(row, text: "+ 2 more files"))
    }

    @Test("Exactly five files are all listed with no overflow line",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func showsNoOverflowLineAtExactlyFive() {
        let row = Self.makeRow(
            violations: Self.makeViolations([
                ("One.swift", 5), ("Two.swift", 4), ("Three.swift", 3),
                ("Four.swift", 2), ("Five.swift", 1)
            ])
        )

        #expect(Self.detailContains(row, text: "Five.swift"))
        #expect(!Self.detailContains(row, text: "+ 0 more files"))
        #expect(!Self.detailContains(row, text: "+ 1 more files"))
    }

    // MARK: - Example violation

    @Test("The first violation is shown with its file, line and message",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func showsFirstViolationDetails() {
        let violations = [
            Violation(
                ruleID: "force_cast",
                filePath: "Sources/Thing.swift",
                line: 42,
                severity: .warning,
                message: "Force casts should be avoided"
            )
        ]
        let row = Self.makeRow(violations: violations)

        #expect(Self.detailContains(row, text: "Sources/Thing.swift"))
        #expect(Self.detailContains(row, text: "Line 42"))
        #expect(Self.detailContains(row, text: "Force casts should be avoided"))
    }

    @Test("An entry with no violation details says so",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func showsPlaceholderWithoutViolations() {
        // A result can carry a count without the individual violations.
        let impact = RuleImpactResult(
            ruleId: "force_cast",
            violationCount: 4,
            violations: [],
            affectedFiles: ["A.swift"],
            simulationDuration: 0.1
        )
        let entry = RuleAuditEntry(
            rule: Self.makeRule(),
            impactResult: impact,
            isCurrentlyEnabled: false
        )
        let row = RuleAuditRow(
            entry: entry,
            isExpanded: true,
            isSelected: false,
            totalSwiftFiles: 20,
            maxViolationCount: 50,
            onToggleExpand: {},
            onToggleSelect: {},
            onEnable: {}
        )

        #expect(Self.detailContains(row, text: "No violation details available"))
    }

    @Test("An error-severity violation is labelled as an error",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func labelsErrorSeverity() throws {
        let row = Self.makeRow(
            violations: Self.makeViolations([("A.swift", 1)], severity: .error)
        )

        let hasErrorLabel = (try? row.expandedDetail.inspect().find { view in
            (try? view.accessibilityLabel().string()) == "Error"
        }) != nil

        #expect(hasErrorLabel)
    }

    @Test("A warning-severity violation is labelled as a warning",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func labelsWarningSeverity() throws {
        let row = Self.makeRow(
            violations: Self.makeViolations([("A.swift", 1)], severity: .warning)
        )

        let hasWarningLabel = (try? row.expandedDetail.inspect().find { view in
            (try? view.accessibilityLabel().string()) == "Warning"
        }) != nil

        #expect(hasWarningLabel)
    }

    // MARK: - Autocorrection

    @Test("An auto-fixable rule advertises that every violation can be fixed",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func showsAutocorrectionNote() {
        let row = Self.makeRow(
            violations: Self.makeViolations([("A.swift", 3)]),
            supportsAutocorrection: true
        )

        #expect(Self.detailContains(row, text: "All 3 violations are auto-fixable"))
    }

    @Test("A rule without autocorrection shows no such note",
          .disabled("ViewInspector 0.10.3 traps on GeometryReader on macOS 27"))
    func hidesAutocorrectionNote() {
        let row = Self.makeRow(
            violations: Self.makeViolations([("A.swift", 3)]),
            supportsAutocorrection: false
        )

        #expect(!Self.detailContains(row, text: "All 3 violations are auto-fixable"))
    }
}
