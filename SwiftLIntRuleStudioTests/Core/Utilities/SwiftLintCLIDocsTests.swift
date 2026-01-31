//
//  SwiftLintCLIDocsTests.swift
//  SwiftLIntRuleStudioTests
//
//  Docs generation tests for SwiftLintCLI
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLIDocsTests {
    @Test("SwiftLintCLI generateDocsForRule uses cached docs")
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
                return (Data("1.0.0\n".utf8), Data())
            }
            return (Data(), Data())
        }

        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Cached docs")
    }

    @Test("SwiftLintCLI generateDocsForRule reads existing docs directory")
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
                return (Data("\(version)\n".utf8), Data())
            }
            return (Data(), Data())
        }

        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Existing docs")
    }

    @Test("SwiftLintCLI generateDocsForRule creates docs after generate-docs")
    func testGenerateDocsCreatesDocs() async throws {
        let cacheManager = await MainActor.run { CacheManager.createForTesting() }
        let ruleId = "generated_rule"
        let version = "8.8.8"

        let runner: SwiftLintCommandRunner = { _, arguments in
            if arguments == ["version"] {
                return (Data("\(version)\n".utf8), Data())
            }
            if let pathIndex = arguments.firstIndex(of: "--path"),
               arguments.contains("generate-docs"),
               arguments.indices.contains(pathIndex + 1) {
                let docsDir = URL(fileURLWithPath: arguments[pathIndex + 1], isDirectory: true)
                try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
                let docFile = docsDir.appendingPathComponent("\(ruleId).md")
                try? Data("Generated docs".utf8).write(to: docFile)
            }
            return (Data(), Data())
        }

        let cli = await SwiftLintCLI(cacheManager: cacheManager, commandRunner: runner)
        let content = try await cli.generateDocsForRule(ruleId: ruleId)
        #expect(content == "Generated docs")
    }
}
