//
//  SwiftLintCLIEnvironmentTests.swift
//  SwiftLIntRuleStudioTests
//
//  Environment and argument builder tests for SwiftLintCLI
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLIEnvironmentTests {
    @Test("SwiftLintCLI buildEnvironment adds Homebrew paths")
    func testBuildEnvironmentAddsPaths() {
        let base = ["PATH": "/usr/bin:/bin"]
        let env = SwiftLintCLI.buildEnvironment(base: base)
        #expect(env["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:") == true)
    }

    @Test("SwiftLintCLI buildEnvironment sets default PATH")
    func testBuildEnvironmentSetsDefault() {
        let env = SwiftLintCLI.buildEnvironment(base: [:])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    @Test("SwiftLintCLI builds shell command with escaping")
    func testBuildShellCommandEscaping() {
        let command = SwiftLintCLI.buildShellCommand(
            command: "swiftlint",
            arguments: ["rules", "my rule", "path/with space"]
        )
        #expect(command.contains("swiftlint") == true)
        #expect(command.contains("'my rule'") == true)
        #expect(command.contains("'path/with space'") == true)
    }

    @Test("SwiftLintCLI buildLintArguments includes config when present")
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

        let arguments = await SwiftLintCLI.buildLintArguments(
            configPath: configURL,
            workspacePath: tempDir,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config") == true)
        #expect(arguments.contains(configURL.path) == true)
    }

    @Test("SwiftLintCLI buildLintArguments skips config when missing")
    func testBuildLintArgumentsSkipsConfig() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let fileExists: SwiftLintFileExists = { _ in false }

        let arguments = await SwiftLintCLI.buildLintArguments(
            configPath: configURL,
            workspacePath: tempDir,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config") == false)
        #expect(arguments.contains(configURL.path) == false)
    }
}
