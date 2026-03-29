//
//  RuleDetailViewModelDiffTests.swift
//  SwiftLintRuleStudioTests
//
//  Diff generation tests for RuleDetailViewModel
//

import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@MainActor
struct RuleDetailViewModelDiffTests {
    @Test("RuleDetailViewModel generates diff for new rule")
    func testGenerateDiffNewRule() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
        }

        let (diff, hasNewRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.addedRules.contains("new_rule") == true)
        }

        #expect(diff != nil)
        #expect(hasNewRule)
    }

    @Test("RuleDetailViewModel generates diff for modified rule")
    func testGenerateDiffModifiedRule() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }

        let (diff, hasModifiedRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.modifiedRules.contains("test_rule") == true)
        }

        #expect(diff != nil)
        #expect(hasModifiedRule)
    }

    @Test("RuleDetailViewModel generates diff for disabled rule")
    func testGenerateDiffDisabledRule() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(false)
        }

        let (diff, hasModifiedRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.modifiedRules.contains("test_rule") == true)
        }

        #expect(diff != nil)
        #expect(hasModifiedRule)
    }
}
