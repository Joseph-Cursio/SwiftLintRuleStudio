import Foundation
@testable import SwiftLintInProcessBackend
import Testing

/// In-process, `${PWD}` in a config would expand to the app's working directory, which is one
/// for every lint, so a config using it is refused with a reason rather than linting nothing.
@MainActor
@Suite(.serialized)
struct InProcessWorkingDirectoryTests {
    /// YAML decodes `\x24` to `$` before SwiftLint expands the variable.
    @Test("A config using ${PWD} is refused, with a reason", arguments: [
        "included:\n  - ${PWD}/Sources\n",
        "included:\n  - \"\\x24{PWD}/Sources\"\n"
    ])
    func workingDirectoryVariableIsRefused(config: String) throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessWorkingDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        try config.write(
            to: workspace.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "let a = 1\n".write(
            to: workspace.appendingPathComponent("Sources/A.swift"),
            atomically: true,
            encoding: .utf8
        )

        let error = #expect(throws: InProcessConfigurationError.self) {
            _ = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        }
        #expect(error?.localizedDescription.contains("${PWD}") == true)
    }

    /// SwiftLint expands `${…}` in values, never in comments.
    @Test("A config that mentions ${PWD} only in a comment is linted", arguments: [false, true])
    func workingDirectoryInCommentIsLinted(nested: Bool) throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessWorkingDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        let folder = nested ? workspace.appendingPathComponent("Nested", isDirectory: true) : workspace
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try "disabled_rules:\n  - todo\n".write(
            to: workspace.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "# Paths here are relative to ${PWD}.\nopt_in_rules:\n  - empty_count\n".write(
            to: folder.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "let values: [Int] = []\nlet isEmpty = values.count == 0\n".write(
            to: folder.appendingPathComponent("A.swift"),
            atomically: true,
            encoding: .utf8
        )

        let data = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(json.contains { $0["rule_id"] as? String == "empty_count" })
    }
}
