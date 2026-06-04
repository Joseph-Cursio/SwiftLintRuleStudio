//
//  SwiftLintCLIEnvironmentTests.swift
//  SwiftLintRuleStudioTests
//
//  Environment and argument builder tests for SwiftLintCLIActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLIEnvironmentTests {
    @Test("SwiftLintCLIActor buildLintArguments includes config when present")
    func testBuildLintArgumentsIncludesConfig() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        try Data("rules: {}".utf8).write(to: configURL)
        let fileExists: SwiftLintFileExists = { path in
            FileManager.default.fileExists(atPath: path)
        }

        let arguments = await SwiftLintCLIActor.buildLintArguments(
            configPath: configURL,
            workspacePath: tempDir,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config"))
        #expect(arguments.contains(configURL.path))
    }

    @Test("SwiftLintCLIActor buildLintArguments skips config when missing")
    func testBuildLintArgumentsSkipsConfig() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let fileExists: SwiftLintFileExists = { _ in false }

        let arguments = await SwiftLintCLIActor.buildLintArguments(
            configPath: configURL,
            workspacePath: tempDir,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config") == false)
        #expect(arguments.contains(configURL.path) == false)
    }
}
