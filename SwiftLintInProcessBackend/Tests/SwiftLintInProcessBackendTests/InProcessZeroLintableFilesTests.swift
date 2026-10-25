import Foundation
import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// `swiftlint lint` fails when it finds nothing to lint. In-process, an empty lint returned
/// no violations instead, so a folder nobody linted read as clean — and in a rule simulation
/// every rule measured 0, "safe to enable".
@MainActor
@Suite(.serialized)
struct InProcessZeroLintableFilesTests {
    /// A workspace with a `.swiftlint.yml` holding `config` and no Swift files at all.
    private func makeEmptyWorkspace(config: String = "disabled_rules:\n  - todo\n") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessZeroLintableFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try config.write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("A lint that finds no Swift files fails, as swiftlint lint does")
    func emptyLintFails() async throws {
        let root = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let error = await #expect(throws: (any Error).self) {
            _ = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: root)
        }

        #expect(error?.localizedDescription.contains("No lintable files found") == true)
    }

    @Test("Workspace analysis with an explicit config fails the same way")
    func emptyLintWithConfigPathFails() async throws {
        let root = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: (any Error).self) {
            _ = try await SwiftLintInProcessActor().executeLintCommand(
                configPath: root.appendingPathComponent(".swiftlint.yml"),
                workspacePath: root
            )
        }
    }

    @Test("allow_zero_lintable_files lets an empty lint succeed with no violations")
    func allowZeroLintableFiles() async throws {
        let root = try makeEmptyWorkspace(config: "allow_zero_lintable_files: true\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: root)

        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(report.isEmpty)
    }

    @Test("Simulating rules over a workspace with nothing to lint fails them, never calls them safe")
    func simulationOverNothingFails() async throws {
        let root = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(path: root)

        let batch = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRules(
            ruleIds: ["force_cast", "empty_count"],
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            classification: RuleClassification(optInRuleIds: ["empty_count"])
        )

        #expect(batch.safeRules.isEmpty)
        for result in batch.results {
            guard case .failed(let reason) = result.measurement else {
                Issue.record("\(result.ruleId) was \(result.measurement), not a failure")
                continue
            }
            #expect(reason?.contains("No lintable files found") == true)
        }
    }
}
