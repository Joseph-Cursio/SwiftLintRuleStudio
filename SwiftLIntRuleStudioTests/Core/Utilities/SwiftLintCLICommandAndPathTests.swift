//
//  SwiftLintCLICommandAndPathTests.swift
//  SwiftLIntRuleStudioTests
//
//  Command and path resolution tests for SwiftLintCLI
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLICommandAndPathTests {
    @Test("SwiftLintCLI executeRulesCommand uses runner")
    func testExecuteRulesCommandUsesRunner() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRulesCommand()

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "swiftlint")
        #expect(calls.first?.1.contains("rules") == true)
    }

    @Test("SwiftLintCLI executeRuleDetailCommand uses runner")
    func testExecuteRuleDetailCommandUsesRunner() async throws {
        let recorder = CommandRecorder()
        let runner: SwiftLintCommandRunner = { command, arguments in
            await recorder.record(command, arguments)
            return (Data("[]".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        _ = try await cli.executeRuleDetailCommand(ruleId: "force_cast")

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.1.contains("force_cast") == true)
    }

    @Test("SwiftLintCLI detects SwiftLint path and caches it")
    func testDetectSwiftLintPathCaching() async throws {
        let map = AsyncMap(values: [
            "/opt/homebrew/bin/swiftlint": true,
            "/usr/local/bin/swiftlint": false
        ])
        let fileExists: SwiftLintFileExists = { path in
            await map.get(path)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
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

    @Test("SwiftLintCLI falls back to shell runner when path missing")
    func testFallbackToShellRunner() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let shellRunner: SwiftLintShellRunner = { command, _, _ in
            #expect(command.contains("swiftlint rules") == true)
            return (Data("ok".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
            cacheManager: cacheManager,
            fileExists: fileExists,
            shellRunner: shellRunner
        )

        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI uses process runner for direct execution")
    func testProcessRunnerDirectExecution() async throws {
        let fileExists: SwiftLintFileExists = { path in
            path == "/opt/homebrew/bin/swiftlint"
        }
        let processRunner: SwiftLintProcessRunner = { url, arguments, environment in
            #expect(url.path == "/opt/homebrew/bin/swiftlint")
            #expect(arguments.contains("rules") == true)
            #expect(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
            return (Data("ok".utf8), Data("warning: ignore".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(
            cacheManager: cacheManager,
            fileExists: fileExists,
            processRunner: processRunner
        )

        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI detectSwiftLintPath throws when missing")
    func testDetectSwiftLintPathThrows() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, fileExists: fileExists)

        await #expect(throws: SwiftLintError.self) {
            _ = try await cli.detectSwiftLintPath()
        }
    }
}
