//
//  RuleDetailViewModelTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for RuleDetailViewModel tests
//

import Foundation
@testable import SwiftLIntRuleStudio

enum RuleDetailViewModelTestHelpers {
    static func createYAMLConfigurationEngine(configPath: URL) async -> YAMLConfigurationEngine {
        await MainActor.run {
            YAMLConfigurationEngine(configPath: configPath)
        }
    }

    static func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil,
        workspaceManager: WorkspaceManager? = nil
    ) async -> RuleDetailViewModel {
        await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine, workspaceManager: workspaceManager)
        }
    }

    static func createTempConfigFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        if !content.isEmpty {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
        }

        return configFile
    }

    static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func createTestRule(id: String, isOptIn: Bool) -> Rule {
        Rule(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Test rule description",
            category: .style,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: .warning,
            markdownDocumentation: nil
        )
    }
}
