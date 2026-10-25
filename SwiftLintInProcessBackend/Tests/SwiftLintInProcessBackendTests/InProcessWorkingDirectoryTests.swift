import Foundation
@testable import SwiftLintInProcessBackend
import Testing

/// In-process, `${PWD}` in a config would expand to the app's working directory, which is one
/// for every lint, so a config using it is refused with a reason rather than linting nothing.
@MainActor
@Suite(.serialized)
struct InProcessWorkingDirectoryTests {
    @Test("A config using ${PWD} is refused, with a reason")
    func workingDirectoryVariableIsRefused() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessWorkingDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }
        try "included:\n  - ${PWD}/Sources\n".write(
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
}
