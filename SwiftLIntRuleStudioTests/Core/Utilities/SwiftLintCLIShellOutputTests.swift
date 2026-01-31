//
//  SwiftLintCLIShellOutputTests.swift
//  SwiftLIntRuleStudioTests
//
//  Stderr handling and shell execution tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLIShellOutputTests {
    @Test("SwiftLintCLI treats command not found as notFound")
    func testCommandNotFoundError() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data(), Data("swiftlint: command not found".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            #expect(false, "Expected notFound error")
        } catch let error as SwiftLintError {
            switch error {
            case .notFound:
                #expect(true)
            default:
                #expect(false, "Expected notFound error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLI treats stderr error as executionFailed")
    func testExecutionFailedOnErrorStderr() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data(), Data("error: bad things happened".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.executeRulesCommand()
            #expect(false, "Expected executionFailed error")
        } catch let error as SwiftLintError {
            switch error {
            case .executionFailed:
                #expect(true)
            default:
                #expect(false, "Expected executionFailed error")
            }
        } catch {
            #expect(false, "Expected SwiftLintError")
        }
    }

    @Test("SwiftLintCLI executeCommandViaShell falls back to shell execution")
    func testExecuteCommandViaShellFallbackUsesShell() async throws {
        let fileExists: SwiftLintFileExists = { _ in false }
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, fileExists: fileExists)

        let output = try await cli.executeCommandViaShell(command: "echo", arguments: ["hello"])
        let outputString = String(data: output, encoding: .utf8)
        #expect(outputString?.contains("hello") == true)
    }

    @Test("SwiftLintCLI ignores warning stderr")
    func testWarningStderrDoesNotFail() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("ok".utf8), Data("warning: something".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRulesCommand()
        #expect(String(data: output, encoding: .utf8) == "ok")
    }

    @Test("SwiftLintCLI ignores invalid rule identifier stderr")
    func testInvalidRuleIdentifierDoesNotFail() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("ok".utf8), Data("error: is not a valid rule identifier".utf8))
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let output = try await cli.executeRuleDetailCommand(ruleId: "unknown_rule")
        #expect(String(data: output, encoding: .utf8) == "ok")
    }
}
