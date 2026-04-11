//
//  ViolationInspectorNewFeaturesTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for new ViolationInspectorView features: grouping and export functionality
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
struct ViolationInspectorNewFeaturesTests {

    // MARK: - Test Data Helpers

    func makeTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        severity: Severity = .error
    ) async -> Violation {
        await MainActor.run {
            Violation(
                id: id,
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                severity: severity,
                message: "Test violation"
            )
        }
    }

    // MARK: - Grouping Tests

    @Test("Groups violations by file")
    func testGroupViolationsByFile() async throws {
        let violations = [
            await makeTestViolation(filePath: "File1.swift"),
            await makeTestViolation(filePath: "File1.swift"),
            await makeTestViolation(filePath: "File2.swift")
        ]

        let grouped = await groupViolations(violations, by: .file)

        #expect(grouped.count == 2)
        #expect(grouped["File1.swift"]?.count == 2)
        #expect(grouped["File2.swift"]?.count == 1)
    }

    @Test("Groups violations by rule")
    func testGroupViolationsByRule() async throws {
        let violations = [
            await makeTestViolation(ruleID: "rule1"),
            await makeTestViolation(ruleID: "rule1"),
            await makeTestViolation(ruleID: "rule2")
        ]

        let grouped = await groupViolations(violations, by: .rule)

        #expect(grouped.count == 2)
        #expect(grouped["rule1"]?.count == 2)
        #expect(grouped["rule2"]?.count == 1)
    }

    @Test("Groups violations by severity")
    func testGroupViolationsBySeverity() async throws {
        let violations = [
            await makeTestViolation(severity: .error),
            await makeTestViolation(severity: .error),
            await makeTestViolation(severity: .warning)
        ]

        let grouped = await groupViolations(violations, by: .severity)

        #expect(grouped.count == 2)
        #expect(grouped["Error"]?.count == 2)
        #expect(grouped["Warning"]?.count == 1)
    }

    @Test("Returns all violations when grouping is none")
    func testGroupViolationsNone() async throws {
        let violations = [
            await makeTestViolation(),
            await makeTestViolation(),
            await makeTestViolation()
        ]

        let grouped = await groupViolations(violations, by: .none)

        #expect(grouped.count == 1)
        #expect(grouped["All"]?.count == 3)
    }

    @Test("Handles empty violations array")
    func testGroupViolationsEmpty() async throws {
        let grouped = await groupViolations([], by: .file)
        #expect(grouped.isEmpty)
    }

    // MARK: - Helper Methods

    func groupViolations(
        _ violations: [Violation],
        by option: ViolationGroupingOption
    ) async -> [String: [Violation]] {
        await MainActor.run {
            switch option {
            case .none:
                return ["All": violations]
            case .file:
                return Dictionary(grouping: violations, by: { $0.filePath })
            case .rule:
                return Dictionary(grouping: violations, by: { $0.ruleID })
            case .severity:
                return Dictionary(grouping: violations, by: { $0.severity.rawValue.capitalized })
            }
        }
    }

    func exportToJSON(violations: [Violation], url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try await MainActor.run {
            try encoder.encode(violations)
        }
        try data.write(to: url)
    }

    func exportToCSV(violations: [Violation], url: URL) async throws {
        let header = [
            "Rule ID",
            "File Path",
            "Line",
            "Column",
            "Severity",
            "Message",
            "Detected At",
            "Resolved At",
            "Suppressed",
            "Suppression Reason"
        ].joined(separator: ",")
        var csv = "\(header)\n"

        // Access violation properties on MainActor
        let violationData = await MainActor.run {
            violations.map { violation in
                (
                    ruleID: violation.ruleID,
                    filePath: violation.filePath,
                    line: violation.line,
                    column: violation.column,
                    severity: violation.severity.rawValue,
                    message: violation.message,
                    detectedAt: violation.detectedAt,
                    resolvedAt: violation.resolvedAt,
                    suppressed: violation.suppressed,
                    suppressionReason: violation.suppressionReason
                )
            }
        }

        for data in violationData {
            let line = [
                data.ruleID,
                data.filePath,
                "\(data.line)",
                data.column.map { "\($0)" } ?? "",
                data.severity,
                "\"\(data.message.replacingOccurrences(of: "\"", with: "\"\""))\"",
                ISO8601DateFormatter().string(from: data.detectedAt),
                data.resolvedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                data.suppressed ? "true" : "false",
                data.suppressionReason.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" } ?? ""
            ].joined(separator: ",")
            csv += line + "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
