import Foundation
import os
import SwiftLintCLISeam
@testable import SwiftLintInProcessBackend
import Testing

/// In the sandboxed Explorer, a workspace closed or replaced while it is being linted gives up
/// its security scope, after which its files can still be found but not read. SwiftLint ends
/// the process — in-process, the app — on a nested config it has found but can't read.
///
/// These stand in for the scope and for its loss: a stand-in scope that counts its ending, and
/// a config with no read permission. Whether the sandbox denies reads once a real
/// security-scoped URL stops being accessed is not exercised here.
struct InProcessSecurityScopeTests {
    private static let source = "let values: [Int] = []\nlet isEmpty = values.count == 0\n"

    /// A workspace with a nested config, which SwiftLint loads as the lint begins.
    private static func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessSecurityScopeTests-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in [
            ("Root.swift", source),
            ("Nested/.swiftlint.yml", "disabled_rules:\n  - empty_count\n"),
            ("Nested/Inner.swift", source)
        ] {
            let file = workspace.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return workspace
    }

    @Test("A workspace's scope released mid-lint stays open until the lint is done")
    func scopeReleasedMidLintStaysOpen() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let scopes = HeldSecurityScopes()
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let hold = scopes.hold { stops.withLock { $0 += 1 } }
        let stopsWhileLinting = OSAllocatedUnfairLock<Int?>(initialState: nil)

        _ = try await SwiftLintInProcessActor(securityScopes: scopes).executeLintCommand(
            configPath: nil,
            workspacePath: workspace
        ) { progress in
            guard progress.filesLinted == 0 else { return }
            scopes.release(hold)
            let count = stops.withLock { $0 }
            stopsWhileLinting.withLock { $0 = count }
        }

        #expect(stopsWhileLinting.withLock { $0 } == 0)
        #expect(stops.withLock { $0 } == 1)
    }

    /// A lint that starts after the scope has ended can't read through it, and must fail on the
    /// backend's own checks before SwiftLint loads the config.
    @Test("A lint of a workspace whose nested config can't be read fails rather than ending the app")
    func unreadableNestedConfigFailsTheLint() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let nested = workspace.appendingPathComponent("Nested/.swiftlint.yml")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: nested.path)

        // The guard first, on its own: were it to miss this config, linting below would end the
        // test process rather than fail the test.
        let guarded = (try? InProcessConfiguration.checkNestedConfigs(in: workspace)) == nil
        guard guarded else {
            Issue.record("the nested-config guard read a config with no read permission; not linting")
            return
        }

        await #expect(throws: InProcessConfigurationError.self) {
            _ = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: workspace)
        }
    }
}
