//
//  SwiftLintCLILintCommandTests.swift
//  SwiftLIntRuleStudioTests
//
//  Lint command tests for SwiftLintCLI
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLILintCommandTests {
    @Test("SwiftLintCLI executeLintCommand builds arguments")
    func testExecuteLintCommandArguments() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        try Data("rules: {}".utf8).write(to: configURL)

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: configURL, workspacePath: tempDir)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1.contains("lint") == true)
        #expect(calls.first?.1.contains("--config") == true)
        #expect(calls.first?.1.contains(configURL.path) == true)
        #expect(calls.first?.1.last == tempDir.path)
    }

    @Test("SwiftLintCLI executeLintCommand skips missing config")
    func testExecuteLintCommandSkipsMissingConfig() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let missingConfigURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeLintCommand(configPath: missingConfigURL, workspacePath: tempDir)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.1.contains("--config") == false)
        #expect(calls.first?.1.contains(missingConfigURL.path) == false)
    }
}
