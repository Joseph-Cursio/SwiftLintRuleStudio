import Foundation
@testable import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// The core rules — `custom_rules` and `superfluous_disable_command` — which the `swiftlint` CLI
/// registers beside the built-in ones. The in-process backend registered only the built-in rules,
/// so SwiftLint read both as unknown identifiers: neither ever ran, and the Explorer didn't list them.
@Suite(.serialized)
struct InProcessCoreRulesTests {
    private func makeWorkspace(config: String, source: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessCoreRulesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try source.write(to: folder.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        try config.write(to: folder.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return folder
    }

    private func ruleIDs(in workspace: URL) async throws -> [String] {
        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: workspace)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return json.compactMap { $0["rule_id"] as? String }.sorted()
    }

    /// The `swiftlint rules` table row for `id`, split into its columns.
    private func catalogRow(_ id: String) throws -> [String] {
        let table = try #require(String(bytes: try SwiftLintInProcessActor().executeRulesCommand(), encoding: .utf8))
        let rows = table.split(separator: "\n").map {
            $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return try #require(rows.first { $0.first == id })
    }

    @Test("The rules catalog lists both core rules, and only custom_rules as needing SourceKit")
    func catalogListsCoreRules() throws {
        // identifier | opt-in | correctable | enabled | kind | analyzer | uses sourcekit
        #expect(try catalogRow("superfluous_disable_command").last == "no")
        #expect(try catalogRow("custom_rules").last == "yes")
        let description = SwiftLintInProcessActor.ruleDescription(forID: "superfluous_disable_command")
        #expect(description?.name == "Superfluous Disable Command")
    }

    @Test("superfluous_disable_command reports a disable that suppressed nothing")
    func superfluousDisableCommandRuns() async throws {
        let workspace = try makeWorkspace(
            config: "",
            source: """
                let value: Any = 1
                // swiftlint:disable:next force_cast
                let cast = value as! Int
                // swiftlint:disable:next force_try
                let plain = cast

                """
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(try await ruleIDs(in: workspace) == ["superfluous_disable_command"])
    }

    @Test("Custom rules that all run on SwiftSyntax fail the lint with a reason, rather than end the app")
    func swiftSyntaxCustomRulesAreRefused() async throws {
        // SwiftLint runs these without SourceKit, then asks SourceKit for the syntax map to match
        // them, which with SourceKit off is a fatal error — the `swiftlint` CLI aborts on it too.
        let workspace = try makeWorkspace(
            config: """
                custom_rules:
                  no_number:
                    regex: NSNumber
                    execution_mode: swiftsyntax

                """,
            source: "let number = NSNumber(value: 1)\n"
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let error = await #expect(throws: InProcessConfigurationError.self) {
            _ = try await ruleIDs(in: workspace)
        }
        #expect(error?.localizedDescription.contains("execution_mode: swiftsyntax") == true)
    }

    @Test("Custom rules that need SourceKit are skipped, and a disable naming one is no unknown rule")
    func sourceKitCustomRulesAreSkipped() async throws {
        // As `SWIFTLINT_DISABLE_SOURCEKIT=1 swiftlint lint` reports this workspace: one custom rule
        // needing SourceKit skips them all, and only the disable of a rule nobody defines is flagged.
        let workspace = try makeWorkspace(
            config: """
                custom_rules:
                  no_number:
                    regex: NSNumber
                  no_print:
                    regex: print
                    execution_mode: swiftsyntax

                """,
            source: """
                // swiftlint:disable:next no_number
                let number = NSNumber(value: 1)
                // swiftlint:disable:next not_a_rule
                let b = 2

                """
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        #expect(try await ruleIDs(in: workspace) == ["identifier_name", "superfluous_disable_command"])
    }

    @MainActor
    @Test("The Rule Audit measures superfluous_disable_command in-process")
    func auditMeasuresSuperfluousDisableCommand() async throws {
        let root = try makeWorkspace(
            config: "disabled_rules:\n  - superfluous_disable_command\n",
            source: "// swiftlint:disable:next force_try\nlet plain = 1\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(path: root)

        let result = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRule(
            ruleId: "superfluous_disable_command",
            workspace: workspace,
            baseConfigPath: workspace.configPath
        )

        #expect(result.measurement == .measured)
        #expect(result.violationCount == 1)
    }
}
