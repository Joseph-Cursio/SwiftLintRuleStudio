//
//  SwiftLintCLIShellOutputTests.swift
//  SwiftLintRuleStudioTests
//
//  Exit-code policy tests for SwiftLintCLIActor (mirrors SwiftLint's
//  convention via the shared CLIToolActor: 0/2 succeed, 127 → notFound,
//  anything else → executionFailed — regardless of stderr text).
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLIShellOutputTests {
    @Test("SwiftLintCLIActor treats exit 127 as notFound")
    func testCommandNotFoundError() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            SwiftLintCommandOutput(stdout: Data(), stderr: Data("swiftlint: command not found".utf8), exitCode: 127)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            Issue.record("Expected notFound error")
        } catch let error as SwiftLintError {
            switch error {
            case .notFound:
                #expect(true)
            default:
                Issue.record("Expected notFound error")
            }
        } catch {
            Issue.record("Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLIActor treats a non-success exit code as executionFailed")
    func testExecutionFailedOnNonSuccessExit() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            SwiftLintCommandOutput(stdout: Data(), stderr: Data("error: bad things happened".utf8), exitCode: 70)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            Issue.record("Expected executionFailed error")
        } catch let error as SwiftLintError {
            switch error {
            case .executionFailed:
                #expect(true)
            default:
                Issue.record("Expected executionFailed error")
            }
        } catch {
            Issue.record("Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLIActor treats exit 0 as success regardless of stderr")
    func testWarningStderrDoesNotFail() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            SwiftLintCommandOutput(stdout: Data("ok".utf8), stderr: Data("warning: something".utf8), exitCode: 0)
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLIActor treats exit 2 (serious violations) as success")
    func testExitTwoTreatedAsSuccess() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            SwiftLintCommandOutput(
                stdout: Data("ok".utf8),
                stderr: Data("error: is not a valid rule identifier".utf8),
                exitCode: 2
            )
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRuleDetailCommand(ruleId: "unknown_rule")
        #expect(String(data: output, encoding: .utf8) == "ok")
    }
}
