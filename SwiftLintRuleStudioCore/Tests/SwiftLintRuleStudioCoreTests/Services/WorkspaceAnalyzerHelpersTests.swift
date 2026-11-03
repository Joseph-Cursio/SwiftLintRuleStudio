//
//  WorkspaceAnalyzerHelpersTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What the analyzer settles before it lints: the config, the files, and where they are.
//

import Foundation
import LintStudioCore
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct WorkspaceAnalyzerHelpersTests {
    private func makeAnalyzer() -> WorkspaceAnalyzer {
        WorkspaceAnalyzer(
            swiftLintCLI: WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLIActor(),
            violationStorage: WorkspaceAnalyzerTestHelpers.createMockViolationStorage(),
            fileTracker: FileTracker.createForTesting()
        )
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("the config used is the one given, or else the workspace's, and only a file that exists")
    func resolveConfigPath() throws {
        let folder = TestTempDirectory.make("analyzer-config")
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(path: folder)
        let given = folder.appendingPathComponent("given.yml")
        let analyzer = makeAnalyzer()

        #expect(analyzer.resolveConfigPath(given, workspace: workspace) == nil, "not written yet")
        #expect(analyzer.resolveConfigPath(nil, workspace: workspace) == nil, "not written yet")

        try write("disabled_rules:\n  - todo\n", to: given)
        try write("disabled_rules:\n  - todo\n", to: folder.appendingPathComponent(".swiftlint.yml"))

        #expect(analyzer.resolveConfigPath(given, workspace: workspace) == given)
        #expect(analyzer.resolveConfigPath(nil, workspace: workspace) == workspace.configPath)
    }

    @Test("with onlyChanged, files unchanged since they were tracked are left out; without it, none are")
    func resolveFilesToAnalyze() throws {
        let folder = TestTempDirectory.make("analyzer-changed")
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracked = folder.appendingPathComponent("Tracked.swift")
        let fresh = folder.appendingPathComponent("Fresh.swift")
        try write("let a = 1\n", to: tracked)
        try write("let b = 1\n", to: fresh)
        let analyzer = makeAnalyzer()
        try analyzer.fileTracker.updateTracking(for: tracked.path)

        #expect(analyzer.resolveFilesToAnalyze([tracked, fresh], onlyChanged: true) == [fresh.path])
        #expect(analyzer.resolveFilesToAnalyze([tracked, fresh], onlyChanged: false) == [tracked.path, fresh.path])
    }

    @Test("finding Swift files leaves out build and dependency folders, and files of other kinds")
    func findSwiftFiles() throws {
        let folder = TestTempDirectory.make("analyzer-find")
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = [
            "Sources/A.swift", "Sources/Upper.SWIFT", "Sources/notes.txt", "README.md",
            "Pods/Dep/P.swift", "Build/G.swift"
        ]
        for path in paths {
            try write("", to: folder.appendingPathComponent(path))
        }

        let found = try makeAnalyzer().findSwiftFiles(in: folder)

        #expect(Set(found.map(\.lastPathComponent)) == ["A.swift", "Upper.SWIFT"])
    }
}
