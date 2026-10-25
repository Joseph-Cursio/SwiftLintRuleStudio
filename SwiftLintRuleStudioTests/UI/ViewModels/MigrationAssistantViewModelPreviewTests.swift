//
//  MigrationAssistantViewModelPreviewTests.swift
//  SwiftLintRuleStudioTests
//
//  The migration preview the UI shows, against the real migration assistant and
//  a real file: MigrationAssistantView offers "Apply All Auto-Fixes" only when
//  the view model says the plan rewrites the file.
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

/// A CLI that only reports its version; the migration never lints.
private struct FixedVersionCLI: SwiftLintCLIProtocol {
    let version: String

    func getVersion() throws -> String { version }
    func detectSwiftLintPath() throws -> URL { URL(fileURLWithPath: "/usr/bin/swiftlint") }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId _: String) throws -> String { "" }
    func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
}

@MainActor
struct MigrationAssistantViewModelPreviewTests {

    /// What the view showed and what the file holds afterwards.
    private struct Outcome {
        let preview: YAMLConfigurationEngine.ConfigDiff
        /// Whether the view offered "Apply All Auto-Fixes".
        let offered: Bool
        let saved: String
    }

    /// Detects, previews and applies a migration of `yaml` from `fromVersion` to `toVersion` the
    /// way the view does, and returns the preview, whether Apply was offered, and the file's
    /// text afterwards.
    private func migrate(
        _ yaml: String, from fromVersion: String, to toVersion: String
    ) async throws -> Outcome {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = MigrationAssistantViewModel(
            assistant: MigrationAssistant(),
            swiftLintCLI: FixedVersionCLI(version: toVersion),
            configPath: configPath
        )
        viewModel.previousVersion = fromVersion
        viewModel.detectMigrations()
        await viewModel.detectTask?.value
        viewModel.previewChanges()
        let preview = try #require(viewModel.previewDiff)
        let offered = viewModel.previewRewritesConfig
        if offered {
            viewModel.applyMigration()
        }
        #expect(viewModel.error == nil)
        return Outcome(preview: preview, offered: offered, saved: try String(contentsOf: configPath, encoding: .utf8))
    }

    /// `rule: error` is a severity shorthand the engine keeps as a passthrough node. Its rename
    /// changed no key of `rules`, so the preview said "No changes needed" and hid Apply.
    @Test("A severity-shorthand rename previews as a change and applies")
    func shorthandRename() async throws {
        let yaml = "redundant_self_in_closure: error\nline_length:\n  warning: 150\n"
        let outcome = try await migrate(yaml, from: "0.62.0", to: "0.63.0")
        #expect(outcome.preview.hasChanges)
        #expect(outcome.offered)
        #expect(outcome.saved.contains("redundant_self: error"))
        #expect(outcome.saved.contains("redundant_self_in_closure") == false)
    }

    @Test("A severity-shorthand removal previews as a change and applies")
    func shorthandRemoval() async throws {
        let yaml = "inert_defer: warning\nline_length: 150\n"
        let outcome = try await migrate(yaml, from: "0.57.0", to: "0.58.0")
        #expect(outcome.preview.hasChanges)
        #expect(outcome.offered)
        #expect(outcome.saved.contains("inert_defer") == false)
        #expect(outcome.saved.contains("line_length: 150"))
    }

    /// SwiftLint reads the alias as `redundant_self`, so the diff reports no change to what it
    /// checks; the rename is still written when the plan is applied.
    @Test("A rename inside a rule list is offered and applies")
    func listOnlyRename() async throws {
        let outcome = try await migrate(
            "opt_in_rules:\n  - redundant_self_in_closure\n", from: "0.62.0", to: "0.63.0"
        )
        #expect(outcome.preview.hasChanges == false)
        #expect(outcome.offered)
        #expect(outcome.saved.contains("- redundant_self\n") || outcome.saved.hasSuffix("- redundant_self"))
        #expect(outcome.saved.contains("redundant_self_in_closure") == false)
    }
}
