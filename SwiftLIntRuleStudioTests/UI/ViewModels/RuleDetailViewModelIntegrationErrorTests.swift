//
//  RuleDetailViewModelIntegrationErrorTests.swift
//  SwiftLIntRuleStudioTests
//
//  Error handling integration tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailVMIntegrationErrorTests {
    @Test("RuleDetailViewModel handles invalid workspace gracefully")
    func testRuleDetailViewModelHandlesInvalidWorkspace() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(rule: rule)

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value

        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        await #expect(throws: RuleConfigurationError.noWorkspace) {
            try await Task { @MainActor in
                try await viewModel.saveConfiguration()
            }.value
        }
    }

    @Test("RuleDetailViewModel handles config file errors gracefully")
    func testRuleDetailViewModelHandlesConfigFileErrors() async throws {
        let invalidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nonexistent")
            .appendingPathComponent(".swiftlint.yml")

        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: invalidPath
        )
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value

        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        do {
            try await Task { @MainActor in
                try viewModel.saveConfiguration()
            }.value
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is CocoaError || error is YAMLConfigError)
        }
    }
}
