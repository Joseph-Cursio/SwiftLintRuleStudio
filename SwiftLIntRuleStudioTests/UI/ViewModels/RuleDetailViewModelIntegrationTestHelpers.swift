//
//  RuleDetailViewModelIntegrationTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for RuleDetailViewModel integration tests
//

import Foundation
@testable import SwiftLIntRuleStudio

enum RuleDetailVMIntegrationHelpers {
    static func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil,
        workspaceManager: WorkspaceManager? = nil
    ) async -> RuleDetailViewModel {
        return await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine, workspaceManager: workspaceManager)
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
