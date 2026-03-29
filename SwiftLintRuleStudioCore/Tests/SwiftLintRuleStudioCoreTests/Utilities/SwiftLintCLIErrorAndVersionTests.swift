//
//  SwiftLintCLIErrorAndVersionTests.swift
//  SwiftLintRuleStudioTests
//
//  Error and version tests for SwiftLintCLIActor
//

import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

struct SwiftLintCLIErrorAndVersionTests {
    @Test("SwiftLintError has correct error descriptions")
    func testSwiftLintErrorDescriptions() {
        let notFoundError = SwiftLintError.notFound
        #expect(notFoundError.errorDescription?.contains("not found") == true)

        let invalidVersionError = SwiftLintError.invalidVersion
        #expect(invalidVersionError.errorDescription?.contains("version") == true)

        let executionError = SwiftLintError.executionFailed(message: "Test error")
        #expect(executionError.errorDescription?.contains("Test error") == true)
    }

    @Test("SwiftLintCLIActor getVersion uses command runner output")
    func testGetVersionUsesRunner() async throws {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data("1.2.3\n".utf8), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let version = try await cli.getVersion()
        #expect(version == "1.2.3")
    }

    @Test("SwiftLintCLIActor getVersion throws on invalid output")
    func testGetVersionInvalidOutput() async {
        let runner: SwiftLintCommandRunner = { _, _ in
            (Data([0xFF, 0xFE]), Data())
        }

        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let cli = await SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)

        do {
            _ = try await cli.getVersion()
            Issue.record("Expected invalidVersion error")
        } catch let error as SwiftLintError {
            switch error {
            case .invalidVersion:
                #expect(true)
            default:
                Issue.record("Expected invalidVersion error")
            }
        } catch {
            Issue.record("Expected SwiftLintError")
        }
    }
}
