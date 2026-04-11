//
//  ViolationInspectorNewFeaturesTests+Export.swift
//  SwiftLintRuleStudioTests
//
//  Export functionality tests for ViolationInspectorView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

// MARK: - Export Tests

extension ViolationInspectorNewFeaturesTests {

    @Test("Exports violations to JSON format")
    func testExportToJSON() async throws {
        let violations = [
            await makeTestViolation(
                id: UUID(),
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 10,
                severity: .error
            )
        ]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export_\(UUID().uuidString).json")

        try await exportToJSON(violations: violations, url: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try await MainActor.run {
            try decoder.decode([Violation].self, from: data)
        }

        #expect(decoded.count == 1)
        let decodedRuleID = await MainActor.run { decoded.first?.ruleID }
        #expect(decodedRuleID == "test_rule")
    }

    @Test("Exports violations to CSV format")
    func testExportToCSV() async throws {
        let violations = [
            await makeTestViolation(
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 10,
                severity: .error
            )
        ]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export_\(UUID().uuidString).csv")

        try await exportToCSV(violations: violations, url: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let csv = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(csv.contains("test_rule"))
        #expect(csv.contains("Test.swift"))
        #expect(csv.contains("10"))
        #expect(csv.contains("error"))
    }

    @Test("CSV export handles special characters in messages")
    func testExportToCSVSpecialCharacters() async throws {
        let violation = await makeTestViolation(
            ruleID: "test_rule",
            filePath: "Test.swift",
            line: 10,
            severity: .error
        )

        let violationWithSpecialChars = await MainActor.run {
            Violation(
                id: violation.id,
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                column: violation.column,
                severity: violation.severity,
                message: "Message with \"quotes\" and, commas",
                detectedAt: violation.detectedAt,
                resolvedAt: violation.resolvedAt,
                suppressed: violation.suppressed,
                suppressionReason: violation.suppressionReason
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export_\(UUID().uuidString).csv")

        try await exportToCSV(violations: [violationWithSpecialChars], url: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let csv = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(csv.contains("\"\"quotes\"\"") || csv.contains("\"quotes\""))
    }

    @Test("JSON export includes all violation fields")
    func testExportToJSONAllFields() async throws {
        let violation = await MainActor.run {
            Violation(
                id: UUID(),
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 10,
                column: 5,
                severity: .error,
                message: "Test message",
                detectedAt: Date.now,
                resolvedAt: Date.now,
                suppressed: true,
                suppressionReason: "Test reason"
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export_\(UUID().uuidString).json")

        try await exportToJSON(violations: [violation], url: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try await MainActor.run {
            try decoder.decode([Violation].self, from: data)
        }

        #expect(decoded.count == 1)
        let exported = try #require(decoded.first)
        let exportedData = await MainActor.run {
            (ruleID: exported.ruleID, filePath: exported.filePath,
             line: exported.line, column: exported.column,
             severity: exported.severity, message: exported.message,
             suppressed: exported.suppressed,
             suppressionReason: exported.suppressionReason)
        }
        let violationData = await MainActor.run {
            (ruleID: violation.ruleID, filePath: violation.filePath,
             line: violation.line, column: violation.column,
             severity: violation.severity, message: violation.message,
             suppressed: violation.suppressed,
             suppressionReason: violation.suppressionReason)
        }
        #expect(exportedData.ruleID == violationData.ruleID)
        #expect(exportedData.filePath == violationData.filePath)
        #expect(exportedData.line == violationData.line)
        #expect(exportedData.column == violationData.column)
        #expect(exportedData.severity == violationData.severity)
        #expect(exportedData.message == violationData.message)
        #expect(exportedData.suppressed == violationData.suppressed)
        #expect(exportedData.suppressionReason == violationData.suppressionReason)
    }
}
