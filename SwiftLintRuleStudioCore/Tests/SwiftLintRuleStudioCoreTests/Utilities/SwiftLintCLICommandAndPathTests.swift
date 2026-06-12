//
//  SwiftLintCLICommandAndPathTests.swift
//  SwiftLintRuleStudioTests
//
//  Command and path resolution tests for SwiftLintCLIActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLICommandAndPathTests {
    @Test("SwiftLintCLIActor executeRulesCommand uses runner")
    func testExecuteRulesCommandUsesRunner() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRulesCommand()

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1.contains("rules") == true)
    }

    @Test("SwiftLintCLIActor executeRuleDetailCommand uses runner")
    func testExecuteRuleDetailCommandUsesRunner() async throws {
        let recorder = CommandRecorderActor()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return SwiftLintCommandOutput(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRuleDetailCommand(ruleId: "force_cast")

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.1.contains("force_cast") == true)
    }

    @Test("SwiftLintCLIActor detects SwiftLint path and caches it")
    func testDetectSwiftLintPathCaching() async throws {
        let map = AsyncMapActor(values: [
            "/opt/homebrew/bin/swiftlint": true,
            "/usr/local/bin/swiftlint": false
        ])
        let fileExists: SwiftLintFileExists = { path in
            await map.get(path)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(
            cacheManager: cacheManager,
            fileExists: fileExists
        )

        let first = try await cli.detectSwiftLintPath()
        #expect(first.path == "/opt/homebrew/bin/swiftlint")

        await map.set("/opt/homebrew/bin/swiftlint", false)
        await map.set("/usr/local/bin/swiftlint", true)
        let second = try await cli.detectSwiftLintPath()
        #expect(second.path == "/usr/local/bin/swiftlint")
    }

    @Test("SwiftLintCLIActor detectSwiftLintPath throws when missing")
    func testDetectSwiftLintPathThrows() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, fileExists: fileExists)

        await #expect(throws: SwiftLintError.self) {
            _ = try await cli.detectSwiftLintPath()
        }
    }
}
