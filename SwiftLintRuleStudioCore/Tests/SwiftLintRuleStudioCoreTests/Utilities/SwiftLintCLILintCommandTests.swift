//
//  SwiftLintCLILintCommandTests.swift
//  SwiftLintRuleStudioTests
//
//  Lint command tests for SwiftLintCLIActor
//

import Foundation
import SwiftLintCLIBackend
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLILintCommandTests {
    @Test("SwiftLintCLIActor executeLintCommand lints in effective (nested) mode")
    func testExecuteLintCommandArguments() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
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
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
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

    @Test("A simulation lint asks SwiftLint for no cache, which would never be read again")
    func simulationLintSkipsTheCache() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
        }
        let mirror = FileManager.default.temporaryDirectory.appendingPathComponent("Mirror-\(UUID().uuidString)")
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)

        _ = try await cli.executeSimulationLintCommand(workspacePath: mirror, onlyRule: nil)
        _ = try await cli.executeLintCommand(configPath: nil, workspacePath: mirror)

        let calls = await recorder.calls
        #expect(calls.first?.1 == ["lint", "--no-cache", "--reporter", "json", mirror.path])
        #expect(calls.last?.1.contains("--no-cache") == false, "analysis keeps its cache")
    }

    @Test("A simulation lint of one rule asks SwiftLint to run that rule alone")
    func simulationLintRunsOnlyTheRule() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
        }
        let mirror = FileManager.default.temporaryDirectory.appendingPathComponent("Mirror-\(UUID().uuidString)")
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)

        _ = try await cli.executeSimulationLintCommand(workspacePath: mirror, onlyRule: "empty_count")

        let calls = await recorder.calls
        #expect(calls.first?.1 == [
            "lint", "--no-cache", "--reporter", "json", "--only-rule", "empty_count", mirror.path
        ])
    }
}
