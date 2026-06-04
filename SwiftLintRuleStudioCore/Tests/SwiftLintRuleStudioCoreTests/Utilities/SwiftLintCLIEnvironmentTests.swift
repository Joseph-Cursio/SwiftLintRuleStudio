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
    @Test("buildLintArguments rootConfigOnly mode forces --config when present")
    func testBuildLintArgumentsRootConfigOnlyIncludesConfig() async throws {
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
            mode: .rootConfigOnly,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config"))
        #expect(arguments.contains(configURL.path))
    }

    @Test("buildLintArguments effective mode omits --config so nested configs apply")
    func testBuildLintArgumentsEffectiveModeOmitsConfig() async throws {
        // Regression guard for the nested-config bug: even when a root config
        // exists, the default (effective) mode must NOT pass --config, because
        // --config disables SwiftLint's nested resolution and over-reports.
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

        #expect(arguments.contains("--config") == false)
        #expect(arguments.contains(configURL.path) == false)
        #expect(arguments.last == tempDir.path)
    }

    @Test("buildLintArguments rootConfigOnly skips config when missing")
    func testBuildLintArgumentsSkipsConfig() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let fileExists: SwiftLintFileExists = { _ in false }

        let arguments = await SwiftLintCLIActor.buildLintArguments(
            configPath: configURL,
            workspacePath: tempDir,
            mode: .rootConfigOnly,
            fileExists: fileExists
        )

        #expect(arguments.contains("--config") == false)
        #expect(arguments.contains(configURL.path) == false)
    }
}
