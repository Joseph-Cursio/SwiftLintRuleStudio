import Foundation
import Testing
@testable import SwiftLintInProcessBackend

@Suite
struct SwiftLintInProcessActorTests {

    /// The core proof: lint a real workspace entirely in-process and get SwiftLint
    /// violations back in the exact JSON shape the app decodes.
    @Test
    func lintsWorkspaceInProcessAndReportsViolations() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slintip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let badSource = """
        class foo {
            func Bar() {
                let x=1
                print(x)
            }
        }
        """
        try badSource.write(
            to: dir.appendingPathComponent("Bad.swift"), atomically: true, encoding: .utf8)

        let backend = SwiftLintInProcessActor()
        let data = try await backend.executeLintCommand(configPath: nil, workspacePath: dir)

        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(json.isEmpty == false)

        // JSON must carry the SwiftLint reporter keys the app relies on.
        let first = try #require(json.first)
        #expect(first["rule_id"] is String)
        #expect(first["reason"] is String)
        #expect(first["file"] is String)

        // 'foo' should be flagged by type_name (SwiftSyntax rule — sandbox-safe).
        let ruleIDs = Set(json.compactMap { $0["rule_id"] as? String })
        #expect(ruleIDs.contains("type_name"))
    }

    @Test
    func rulesCatalogIsAPopulatedPipeTable() async throws {
        let backend = SwiftLintInProcessActor()
        let data = try await backend.executeRulesCommand()
        let text = try #require(String(data: data, encoding: .utf8))

        let dataRows = text.split(separator: "\n")
            .filter { $0.hasPrefix("|") && $0.contains("identifier") == false }
        #expect(dataRows.count > 100)
        // Each data row must split into the >=5 columns the parser needs.
        let columns = try #require(dataRows.first).split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        #expect(columns.count >= 5)
    }

    @Test
    func versionAndDetailAndDocsResolve() async throws {
        let backend = SwiftLintInProcessActor()
        #expect(try await backend.getVersion().isEmpty == false)

        let detail = try await backend.executeRuleDetailCommand(ruleId: "type_name")
        let detailText = try #require(String(data: detail, encoding: .utf8))
        #expect(detailText.contains("type_name"))

        let docs = try await backend.generateDocsForRule(ruleId: "type_name")
        #expect(docs.contains("#"))
    }
}
