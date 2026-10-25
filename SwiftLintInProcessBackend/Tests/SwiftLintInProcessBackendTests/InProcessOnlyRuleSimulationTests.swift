import Foundation
import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// A simulation lints the measured rule alone, in-process as with the CLI: the rule keeps what
/// the configs say about it, including a nested `only_rules` that leaves it out.
@MainActor
@Suite(.serialized)
struct InProcessOnlyRuleSimulationTests {
    private func makeWorkspace(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessOnlyRuleSimulationTests-\(UUID().uuidString)", isDirectory: true)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func counts(
        _ ruleIds: [String],
        in root: URL,
        optIn: Set<String> = []
    ) async throws -> [String: RuleImpactResult] {
        let workspace = Workspace(path: root)
        let batch = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRules(
            ruleIds: ruleIds,
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            classification: RuleClassification(optInRuleIds: optIn)
        )
        return Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0) })
    }

    @Test("A rule linted alone keeps its settings and nested disables, and a nested only_rules keeps it off")
    func ruleAloneKeepsWhatTheConfigsSay() async throws {
        let long = "let aLineLongerThanTwenty = 1\nlet values: [Int] = []\nlet isEmpty = values.count == 0\n"
        let root = try makeWorkspace([
            ".swiftlint.yml": "disabled_rules:\n  - line_length\nline_length:\n  warning: 20\n",
            "A.swift": long,
            "Legacy/.swiftlint.yml": "disabled_rules:\n  - line_length\n",
            "Legacy/B.swift": long,
            "Strict/.swiftlint.yml": "only_rules:\n  - force_cast\n",
            "Strict/C.swift": long
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let results = try await counts(["line_length", "empty_count"], in: root, optIn: ["empty_count"])

        #expect(results["line_length"]?.affectedFiles == ["A.swift"])
        #expect(results["empty_count"]?.affectedFiles == ["A.swift", "Legacy/B.swift"])
    }
}
