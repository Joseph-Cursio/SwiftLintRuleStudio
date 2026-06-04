//
//  SwiftLintCLILintCommandTests.swift
//  SwiftLintRuleStudioTests
//
//  Lint command tests for SwiftLintCLIActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLILintCommandTests {
    @Test("SwiftLintCLIActor executeLintCommand lints in effective (nested) mode")
    func testExecuteLintCommandArguments() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data(), 0)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        try Data("rules: {}".utf8).write(to: configURL)

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: configURL, workspacePath: tempDir)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1.contains("lint") == true)
        // Effective mode must NOT force --config, so SwiftLint applies nested
        // .swiftlint.yml files the way the developer and CI do.
        #expect(calls.first?.1.contains("--config") == false)
        #expect(calls.first?.1.contains(configURL.path) == false)
        #expect(calls.first?.1.last == tempDir.path)
    }

    @Test("SwiftLintCLIActor executeLintCommand skips missing config")
    func testExecuteLintCommandSkipsMissingConfig() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data(), 0)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let missingConfigURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: missingConfigURL, workspacePath: tempDir)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.1.contains("--config") == false)
        #expect(calls.first?.1.contains(missingConfigURL.path) == false)
    }
}
