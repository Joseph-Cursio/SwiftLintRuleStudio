//
//  ViolationInspectorExportTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for violation export: which violations a scope covers, the filename
//  it lands under, and the JSON and CSV written to disk.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("Violation export")
struct ViolationInspectorExportTests {

    // MARK: - Fixtures

    private static func makeViolation(
        ruleID: String = "force_cast",
        filePath: String = "Sources/A.swift",
        line: Int = 1,
        severity: Severity = .warning,
        message: String = "Force casts should be avoided"
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message
        )
    }

    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViolationInspectorExportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Scope

    @Test("The filtered scope exports everything currently shown")
    func filteredScopeExportsEverything() {
        let violations = [Self.makeViolation(line: 1), Self.makeViolation(line: 2)]

        let exported = ViolationInspectorView.violationsForExport(
            scope: .filtered,
            filtered: violations,
            selectedIds: []
        )

        #expect(exported.count == 2)
    }

    @Test("The filtered scope ignores the selection entirely")
    func filteredScopeIgnoresSelection() {
        let violations = [Self.makeViolation(line: 1), Self.makeViolation(line: 2)]

        let exported = ViolationInspectorView.violationsForExport(
            scope: .filtered,
            filtered: violations,
            selectedIds: [violations[0].id]
        )

        #expect(exported.count == 2, "a selection must not narrow the filtered scope")
    }

    @Test("The selected scope exports only the selected violations")
    func selectedScopeExportsSelection() {
        let violations = [
            Self.makeViolation(line: 1),
            Self.makeViolation(line: 2),
            Self.makeViolation(line: 3)
        ]

        let exported = ViolationInspectorView.violationsForExport(
            scope: .selected,
            filtered: violations,
            selectedIds: [violations[0].id, violations[2].id]
        )

        #expect(exported.map(\.line) == [1, 3])
    }

    @Test("A selected violation that is no longer shown is not exported")
    func selectedScopeIntersectsWithFiltered() {
        // Selecting a violation and then narrowing the filter must not smuggle
        // it into the export.
        let shown = Self.makeViolation(line: 1)
        let filteredAway = Self.makeViolation(line: 99)

        let exported = ViolationInspectorView.violationsForExport(
            scope: .selected,
            filtered: [shown],
            selectedIds: [shown.id, filteredAway.id]
        )

        #expect(exported.map(\.id) == [shown.id])
    }

    @Test("The selected scope with nothing selected exports nothing")
    func selectedScopeWithEmptySelection() {
        let exported = ViolationInspectorView.violationsForExport(
            scope: .selected,
            filtered: [Self.makeViolation()],
            selectedIds: []
        )

        #expect(exported.isEmpty)
    }

    @Test("Export preserves the order violations are shown in")
    func exportPreservesOrder() {
        let violations = (1...5).map { Self.makeViolation(line: $0) }

        let exported = ViolationInspectorView.violationsForExport(
            scope: .selected,
            filtered: violations,
            selectedIds: Set(violations.map(\.id))
        )

        #expect(exported.map(\.line) == [1, 2, 3, 4, 5])
    }

    // MARK: - Filename

    @Test("The filename records the scope and format")
    func filenameRecordsScopeAndFormat() {
        let json = ViolationInspectorView.exportFileName(scope: .filtered, format: .json)
        let csv = ViolationInspectorView.exportFileName(scope: .selected, format: .csv)

        #expect(json.hasPrefix("violations_filtered_"))
        #expect(json.hasSuffix(".json"))
        #expect(csv.hasPrefix("violations_selected_"))
        #expect(csv.hasSuffix(".csv"))
    }

    @Test("The filename carries a sortable timestamp")
    func filenameCarriesTimestamp() throws {
        let name = ViolationInspectorView.exportFileName(scope: .filtered, format: .json)

        // violations_filtered_<yyyyMMdd_HHmmss>.json
        let stamp = name
            .replacingOccurrences(of: "violations_filtered_", with: "")
            .replacingOccurrences(of: ".json", with: "")
        let pattern = try Regex(#"^\d{8}_\d{6}$"#)

        #expect(stamp.wholeMatch(of: pattern) != nil, "unexpected name: \(name)")
    }

    @Test("The filename is safe to write to disk")
    func filenameIsSafe() {
        let name = ViolationInspectorView.exportFileName(scope: .selected, format: .csv)
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>| ")

        #expect(name.rangeOfCharacter(from: unsafe) == nil)
    }

    // MARK: - JSON

    @Test("JSON export writes a decodable file")
    func jsonExportRoundTrips() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("violations.json")

        let violations = [
            Self.makeViolation(ruleID: "force_cast", line: 7),
            Self.makeViolation(ruleID: "line_length", line: 42, severity: .error)
        ]

        try ViolationInspectorView.exportToJSON(violations: violations, url: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Violation].self, from: Data(contentsOf: url))

        #expect(decoded.count == 2)
        #expect(decoded.map(\.ruleID) == ["force_cast", "line_length"])
        #expect(decoded.map(\.line) == [7, 42])
        #expect(decoded[1].severity == .error)
    }

    @Test("JSON export is stable across runs")
    func jsonExportIsDeterministic() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.json")
        let second = directory.appendingPathComponent("second.json")

        let violations = [Self.makeViolation(ruleID: "b_rule"), Self.makeViolation(ruleID: "a_rule")]

        try ViolationInspectorView.exportToJSON(violations: violations, url: first)
        try ViolationInspectorView.exportToJSON(violations: violations, url: second)

        // Keys are sorted, so the same input must produce byte-identical output
        // — otherwise exports churn in diffs.
        #expect(try Data(contentsOf: first) == (try Data(contentsOf: second)))
    }

    @Test("Exporting no violations writes an empty JSON array")
    func jsonExportHandlesEmptyInput() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("empty.json")

        try ViolationInspectorView.exportToJSON(violations: [], url: url)

        let decoded = try JSONDecoder().decode([Violation].self, from: Data(contentsOf: url))
        #expect(decoded.isEmpty)
    }

    @Test("JSON export overwrites an existing file")
    func jsonExportOverwrites() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("violations.json")

        try "stale contents".write(to: url, atomically: true, encoding: .utf8)
        try ViolationInspectorView.exportToJSON(violations: [Self.makeViolation()], url: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Violation].self, from: Data(contentsOf: url))
        #expect(decoded.count == 1)
    }

    // MARK: - CSV

    @Test("CSV export writes a header and one row per violation")
    func csvExportWritesRows() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("violations.csv")

        let violations = [
            Self.makeViolation(ruleID: "force_cast", line: 7),
            Self.makeViolation(ruleID: "line_length", line: 42)
        ]

        try ViolationInspectorView.exportToCSV(violations: violations, url: url)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.first?.contains("Rule ID") == true)
        #expect(lines.count == violations.count + 1, "header plus one row each")
    }

    @Test("CSV export names every violation's rule")
    func csvExportNamesRules() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("violations.csv")

        try ViolationInspectorView.exportToCSV(
            violations: [
                Self.makeViolation(ruleID: "force_cast"),
                Self.makeViolation(ruleID: "line_length")
            ],
            url: url
        )

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("force_cast"))
        #expect(contents.contains("line_length"))
    }

    @Test("Exporting no violations writes just the CSV header")
    func csvExportHandlesEmptyInput() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("empty.csv")

        try ViolationInspectorView.exportToCSV(violations: [], url: url)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count == 1)
        #expect(lines.first?.contains("Rule ID") == true)
    }

    // MARK: - Format dispatch

    @Test("The format chooses which writer runs")
    func formatSelectsWriter() throws {
        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let jsonURL = directory.appendingPathComponent("out.json")
        let csvURL = directory.appendingPathComponent("out.csv")
        let violations = [Self.makeViolation()]

        try ViolationInspectorView.export(violations: violations, to: jsonURL, as: .json)
        try ViolationInspectorView.export(violations: violations, to: csvURL, as: .csv)

        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)

        #expect(json.hasPrefix("["), "JSON export should be an array")
        #expect(csv.hasPrefix("Rule ID"), "CSV export should start with the header")
    }

    @Test("Writing to an unwritable location throws")
    func exportThrowsOnUnwritablePath() {
        let missing = URL(fileURLWithPath: "/nonexistent-directory-\(UUID().uuidString)/out.json")

        #expect(throws: (any Error).self) {
            try ViolationInspectorView.exportToJSON(violations: [Self.makeViolation()], url: missing)
        }
    }
}
