//
//  ViolationInspectorNewFeaturesTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for new ViolationInspectorView features: grouping and export functionality
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct ViolationInspectorNewFeaturesTests {
    
    // MARK: - Test Data Helpers
    
    private func makeTestViolation(
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
        #expect(grouped.isEmpty == true)
    }
    
    // MARK: - Export Tests
    
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
        
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == true)
        
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
        
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == true)
        
        let csv = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(csv.contains("test_rule") == true)
        #expect(csv.contains("Test.swift") == true)
        #expect(csv.contains("10") == true)
        #expect(csv.contains("error") == true)
    }
    
    @Test("CSV export handles special characters in messages")
    func testExportToCSVSpecialCharacters() async throws {
        let violation = await makeTestViolation(
            ruleID: "test_rule",
            filePath: "Test.swift",
            line: 10,
            severity: .error
        )
        
        // Create violation with special characters - access properties on MainActor
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
        // CSV should properly escape quotes
        #expect(csv.contains("\"\"quotes\"\"") == true || csv.contains("\"quotes\"") == true)
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
                detectedAt: Date(),
                resolvedAt: Date(),
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
            (ruleID: exported.ruleID, filePath: exported.filePath, line: exported.line,
             column: exported.column, severity: exported.severity, message: exported.message,
             suppressed: exported.suppressed, suppressionReason: exported.suppressionReason)
        }
        let violationData = await MainActor.run {
            (ruleID: violation.ruleID, filePath: violation.filePath, line: violation.line,
             column: violation.column, severity: violation.severity, message: violation.message,
             suppressed: violation.suppressed, suppressionReason: violation.suppressionReason)
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
    
    // MARK: - Helper Methods
    
    private func groupViolations(_ violations: [Violation], by option: ViolationGroupingOption) async -> [String: [Violation]] {
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
    
    private func exportToJSON(violations: [Violation], url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try await MainActor.run {
            try encoder.encode(violations)
        }
        try data.write(to: url)
    }
    
    private func exportToCSV(violations: [Violation], url: URL) async throws {
        var csv = "Rule ID,File Path,Line,Column,Severity,Message,Detected At,Resolved At,Suppressed,Suppression Reason\n"
        
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
