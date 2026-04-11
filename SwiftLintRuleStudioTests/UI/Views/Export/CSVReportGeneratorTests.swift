//
//  CSVReportGeneratorTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for CSV report generation
//

import Testing
import Foundation
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
@Suite("CSVReportGenerator Tests")
struct CSVReportGeneratorTests {

    // MARK: - Test Helpers

    private func makeViolation(
        ruleID: String = "line_length",
        filePath: String = "/path/to/File.swift",
        line: Int = 42,
        column: Int? = 10,
        severity: Severity = .warning,
        message: String = "Line too long",
        detectedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        resolvedAt: Date? = nil,
        suppressed: Bool = false,
        suppressionReason: String? = nil
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            column: column,
            severity: severity,
            message: message,
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            suppressed: suppressed,
            suppressionReason: suppressionReason
        )
    }

    // MARK: - Header Tests

    @Test("CSV output starts with correct header row")
    func headerRow() {
        let csv = CSVReportGenerator.generate(violations: [])
        let expectedHeader = "Rule ID,File Path,Line,Column,Severity,Message," +
            "Detected At,Resolved At,Suppressed,Suppression Reason"
        let firstLine = csv.components(separatedBy: "\n").first
        #expect(firstLine == expectedHeader)
    }

    @Test("Empty violations produces header-only output")
    func emptyViolations() {
        let csv = CSVReportGenerator.generate(violations: [])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1) // header only
    }

    // MARK: - Single Violation Tests

    @Test("Single violation produces correct CSV row")
    func singleViolation() {
        let violation = makeViolation()
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)

        let dataRow = lines[1]
        #expect(dataRow.contains("line_length"))
        #expect(dataRow.contains("/path/to/File.swift"))
        #expect(dataRow.contains("42"))
        #expect(dataRow.contains("10"))
        #expect(dataRow.contains("warning"))
        #expect(dataRow.contains("Line too long"))
        #expect(dataRow.contains("false"))
    }

    @Test("Nil column produces empty field in CSV")
    func nilColumn() {
        let violation = makeViolation(column: nil)
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataRow = lines[1]
        // Column field should be empty between two commas
        let fields = dataRow.components(separatedBy: ",")
        // Column is the 4th field (index 3)
        #expect(fields[3].isEmpty)
    }

    @Test("Error severity is reflected in CSV output")
    func errorSeverity() {
        let violation = makeViolation(severity: .error)
        let csv = CSVReportGenerator.generate(violations: [violation])
        #expect(csv.contains("error"))
    }

    @Test("Suppressed violation shows true and reason")
    func suppressedViolation() {
        let violation = makeViolation(
            suppressed: true,
            suppressionReason: "Team decision"
        )
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataRow = lines[1]
        #expect(dataRow.contains("true"))
        #expect(dataRow.contains("Team decision"))
    }

    @Test("Resolved date is included when present")
    func resolvedDate() {
        let resolvedDate = Date(timeIntervalSince1970: 2_000_000)
        let violation = makeViolation(resolvedAt: resolvedDate)
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataRow = lines[1]
        // The resolved date field should not be empty
        let isoFormatter = ISO8601DateFormatter()
        let expectedDateStr = isoFormatter.string(from: resolvedDate)
        #expect(dataRow.contains(expectedDateStr))
    }

    @Test("Nil resolved date produces empty field")
    func nilResolvedDate() {
        let violation = makeViolation(resolvedAt: nil)
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataRow = lines[1]
        // resolvedAt is 8th field (index 7)
        let fields = parseCSVRow(dataRow)
        #expect(fields[7].isEmpty)
    }

    // MARK: - CSV Escaping Tests

    @Test("Values containing commas are properly escaped with quotes")
    func escapesCommas() {
        let violation = makeViolation(message: "Line too long, exceeds limit")
        let csv = CSVReportGenerator.generate(violations: [violation])
        #expect(csv.contains("\"Line too long, exceeds limit\""))
    }

    @Test("Values containing double quotes are properly escaped")
    func escapesDoubleQuotes() {
        let violation = makeViolation(message: "Use \"let\" instead")
        let csv = CSVReportGenerator.generate(violations: [violation])
        #expect(csv.contains("\"Use \"\"let\"\" instead\""))
    }

    @Test("Values containing newlines are properly escaped")
    func escapesNewlines() {
        let violation = makeViolation(message: "Line 1\nLine 2")
        let csv = CSVReportGenerator.generate(violations: [violation])
        #expect(csv.contains("\"Line 1\nLine 2\""))
    }

    @Test("Simple values without special characters are not quoted")
    func noEscapingNeeded() {
        let violation = makeViolation(message: "Simple message")
        let csv = CSVReportGenerator.generate(violations: [violation])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataRow = lines[1]
        // The message should appear without surrounding quotes
        #expect(dataRow.contains("Simple message"))
        #expect(!dataRow.contains("\"Simple message\""))
    }

    // MARK: - Multiple Violations Tests

    @Test("Multiple violations produce correct number of rows")
    func multipleViolations() {
        let violations = [
            makeViolation(ruleID: "rule_one", line: 10),
            makeViolation(ruleID: "rule_two", line: 20),
            makeViolation(ruleID: "rule_three", line: 30)
        ]
        let csv = CSVReportGenerator.generate(violations: violations)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 4) // 1 header + 3 data rows
    }

    @Test("Violations preserve order in CSV output")
    func preservesOrder() {
        let violations = [
            makeViolation(ruleID: "alpha_rule"),
            makeViolation(ruleID: "beta_rule"),
            makeViolation(ruleID: "gamma_rule")
        ]
        let csv = CSVReportGenerator.generate(violations: violations)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines[1].hasPrefix("alpha_rule"))
        #expect(lines[2].hasPrefix("beta_rule"))
        #expect(lines[3].hasPrefix("gamma_rule"))
    }

    // MARK: - Helpers

    /// Simple CSV row parser that respects quoted fields
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
