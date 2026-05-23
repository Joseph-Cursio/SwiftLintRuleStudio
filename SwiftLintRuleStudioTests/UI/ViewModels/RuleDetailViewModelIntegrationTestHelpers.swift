//
//  RuleDetailViewModelIntegrationTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for RuleDetailViewModel integration tests
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

enum RuleDetailViewModelIntegrationTestHelpers {
    static func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil
    ) async -> RuleDetailViewModel {
        await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        }
    }

    static func createYAMLConfigurationEngine(configPath: URL) async -> YAMLConfigurationEngine {
        await MainActor.run {
            YAMLConfigurationEngine(configPath: configPath)
        }
    }

    static func createWorkspaceManager() async -> WorkspaceManager {
        await MainActor.run {
            WorkspaceManager.createForTesting(testName: #function)
        }
    }

    static func createConfigFile(in directory: URL, content: String) throws -> URL {
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }
}
