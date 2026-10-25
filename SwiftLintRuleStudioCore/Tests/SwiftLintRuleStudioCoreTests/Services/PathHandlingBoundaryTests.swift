//
//  PathHandlingBoundaryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The edges of the app's path and URL handling that no test reached: home
//  directory expansion, project markers, GitHub raw URLs, violation paths
//  relative to the workspace, and which files count as config backups.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct PathHandlingBoundaryTests {

    // MARK: - Home-directory expansion

    @Test("`~` and `~/…` expand to the home directory; other paths resolve against the workspace")
    func tildeExpansion() throws {
        let service = XcodeIntegrationService()
        let workspace = Workspace(path: URL(fileURLWithPath: "/tmp/WorkspaceRoot"))
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        #expect(try service.resolveFileURL("~", in: workspace) == home)
        #expect(try service.resolveFileURL("~/Sources/App.swift", in: workspace)
            == home.appendingPathComponent("Sources/App.swift").standardizedFileURL)
        #expect(try service.resolveFileURL("Sources/App.swift", in: workspace)
            == URL(fileURLWithPath: "/tmp/WorkspaceRoot/Sources/App.swift").standardizedFileURL)
    }

    // MARK: - Project markers

    @Test("each project marker is one on its own", arguments: [
        ("App.xcodeproj", true), ("App.xcworkspace", true), ("Package.swift", true), (".swiftpm", true),
        ("App.swift", false), ("Package.resolved", false), ("xcodeproj", false)
    ])
    func projectMarkers(name: String, isMarker: Bool) throws {
        let defaults = try #require(UserDefaults(suiteName: "PathHandlingBoundaryTests-\(UUID().uuidString)"))
        let manager = WorkspaceManager(userDefaults: defaults)
        #expect(manager.isProjectMarker(URL(fileURLWithPath: "/tmp/Project/\(name)")) == isMarker)
    }

    // MARK: - GitHub raw URLs

    @Test("only a github.com blob URL is rewritten to raw content", arguments: [
        ("https://github.com/realm/SwiftLint/blob/main/.swiftlint.yml",
         "https://raw.githubusercontent.com/realm/SwiftLint/main/.swiftlint.yml"),
        ("https://github.com/realm/SwiftLint/tree/main/Source",
         "https://github.com/realm/SwiftLint/tree/main/Source"),
        ("https://gitlab.com/group/project/-/blob/main/.swiftlint.yml",
         "https://gitlab.com/group/project/-/blob/main/.swiftlint.yml")
    ])
    func rawURL(input: String, expected: String) throws {
        let url = try #require(URL(string: input))
        #expect(URLConfigFetcher.resolveToRawURL(url).absoluteString == expected)
    }

    // MARK: - Violation paths

    @Test("a violation under the workspace is reported relative to it; one outside keeps its path")
    func violationPathsRelativeToWorkspace() throws {
        let json = """
            [
              {"rule_id": "force_cast", "reason": "r", "severity": "error",
               "file": "/tmp/WorkspaceRoot/Sources/App.swift", "line": 3, "character": 5},
              {"rule_id": "force_cast", "reason": "r", "severity": "warning",
               "file": "/elsewhere/Other.swift", "line": 1}
            ]
            """
        let simulator = ImpactSimulator(swiftLintCLI: MockSwiftLintCLIActor())
        let violations = try simulator.parseViolations(
            from: Data(json.utf8), workspacePath: URL(fileURLWithPath: "/tmp/WorkspaceRoot")
        )
        #expect(violations.map(\.filePath) == ["Sources/App.swift", "/elsewhere/Other.swift"])
    }

    // MARK: - Config backups

    @Test("only `<config>.<ten-digit seconds>.backup` files are backups, beside the config or in the store")
    func backupsAreNamedExactly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathHandlingBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent(".swiftlint.yml")
        let store = ConfigBackupStore(root: directory.appendingPathComponent("store", isDirectory: true))
        let storeFolder = store.directory(for: config)
        try FileManager.default.createDirectory(at: storeFolder, withIntermediateDirectories: true)
        // Not the app's: another file's backup, another suffix, a backup made by hand with a
        // date in the name, and numbers TimeInterval would have read.
        let notBackups = [
            ".swiftlint.yml",
            ".swiftlint.yml.1700000001.restore",
            "other.yml.1700000002.backup",
            ".swiftlint.yml.20240115.backup",
            ".swiftlint.yml.1700000000.5.backup",
            ".swiftlint.yml.1e9.backup",
            ".swiftlint.yml.nan.backup",
            "config-path.txt"
        ]
        for folder in [directory, storeFolder] {
            for name in notBackups {
                try "rules: {}".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        try "rules: {}".write(
            to: directory.appendingPathComponent(".swiftlint.yml.1700000000.backup"),
            atomically: true,
            encoding: .utf8
        )
        try "rules: {}".write(
            to: storeFolder.appendingPathComponent(".swiftlint.yml.1700000003.backup"),
            atomically: true,
            encoding: .utf8
        )
        let backups = ConfigVersionHistoryService(backups: store).listBackups(for: config)
        // Directory listings spell the temporary folder as /private/var, so compare resolved.
        #expect(backups.map { $0.path.resolvingSymlinksInPath() } == [
            storeFolder.appendingPathComponent(".swiftlint.yml.1700000003.backup"),
            directory.appendingPathComponent(".swiftlint.yml.1700000000.backup")
        ].map { $0.resolvingSymlinksInPath() })
    }
}
