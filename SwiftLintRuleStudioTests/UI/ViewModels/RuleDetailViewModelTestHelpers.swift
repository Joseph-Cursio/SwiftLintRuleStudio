//
//  RuleDetailViewModelTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for RuleDetailViewModel tests
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

enum RuleDetailViewModelTestHelpers {
    static func createYAMLConfigurationEngine(configPath: URL) async -> YAMLConfigurationEngine {
        await MainActor.run {
            YAMLConfigurationEngine(configPath: configPath)
        }
    }

    static func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil
    ) async -> RuleDetailViewModel {
        await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        }
    }

    static func createTempConfigFile(content: String) throws -> URL {
        // Must go through TestTempDirectory rather than building a path under the
        // shared root by hand: only dirs inside this process's run root are safe
        // from another run's cleanup. See TestTempDirectory for the race this had.
        let tempDir = TestTempDirectory.make("ruledetail")

        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        if !content.isEmpty {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
        }

        return configFile
    }

    static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func createTestRule(id: String, isOptIn: Bool, isAnalyzer: Bool = false) -> Rule {
        Rule(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Test rule description",
            category: .style,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer,
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
