//
//  SwiftLintCLIDocsTests.swift
//  SwiftLintRuleStudioTests
//
//  Docs generation tests for SwiftLintCLIActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SwiftLintCLIDocsTests {
    @Test("SwiftLintCLIActor generateDocsForRule uses cached docs")
    func testGenerateDocsUsesCache() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let docsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintCLITestsDocs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        let ruleId = "test_rule"
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        try Data("Cached docs".utf8).write(to: docFile)

        try cacheManager.saveDocsDirectory(docsDir)
        try cacheManager.saveSwiftLintVersion("1.0.0")

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return SwiftLintCommandOutput(stdout: Data("1.0.0\n".utf8), stderr: Data(), exitCode: 0)
            }
            return SwiftLintCommandOutput(stdout: Data(), stderr: Data(), exitCode: 0)
        }

        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Cached docs")
    }

    @Test("SwiftLintCLIActor generateDocsForRule reads existing docs directory")
    func testGenerateDocsUsesExistingDocs() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let ruleId = "existing_rule"
        let version = "9.9.9"

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let docsDir = appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("rule_docs", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let docFile = docsDir.appendingPathComponent("\(ruleId).md")
        try Data("Existing docs".utf8).write(to: docFile)

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return SwiftLintCommandOutput(stdout: Data("\(version)\n".utf8), stderr: Data(), exitCode: 0)
            }
            return SwiftLintCommandOutput(stdout: Data(), stderr: Data(), exitCode: 0)
        }

        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Existing docs")
    }

    @Test("SwiftLintCLIActor generateDocsForRule creates docs after generate-docs")
    func testGenerateDocsCreatesDocs() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let ruleId = "generated_rule"
        let version = "8.8.8"

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return SwiftLintCommandOutput(stdout: Data("\(version)\n".utf8), stderr: Data(), exitCode: 0)
            }
            if let pathIndex = arguments.firstIndex(of: "--path"),
               arguments.contains("generate-docs"),
               arguments.indices.contains(pathIndex + 1) {
                let docsDir = URL(fileURLWithPath: arguments[pathIndex + 1], isDirectory: true)
                try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
                let docFile = docsDir.appendingPathComponent("\(ruleId).md")
                try? Data("Generated docs".utf8).write(to: docFile)
            }
            return SwiftLintCommandOutput(stdout: Data(), stderr: Data(), exitCode: 0)
        }

        let cli = SwiftLintCLIActor(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Generated docs")
    }
}
