//
//  ViolationInspectorNewFeaturesTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for new ViolationInspectorView features: grouping and export functionality
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

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
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                severity: severity,
                message: "Test violation"
            ,
                id: id)
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

        let grouped = await groupViolations(violations, by: .ungrouped)

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
            case .ungrouped:
                return ["All": violations]
            case .file:
                return Dictionary(grouping: violations) { $0.filePath }
            case .rule:
                return Dictionary(grouping: violations) { $0.ruleID }
            case .severity:
                return Dictionary(grouping: violations) { $0.severity.rawValue.capitalized }
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
        let csv = CSVReportGenerator.generate(violations: violations)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
