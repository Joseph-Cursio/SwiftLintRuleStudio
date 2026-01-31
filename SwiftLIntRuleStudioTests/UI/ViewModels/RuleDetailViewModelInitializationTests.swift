//
//  RuleDetailViewModelInitializationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Initialization tests for RuleDetailViewModel
//

import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailViewModelInitializationTests {
    @Test("RuleDetailViewModel initializes with rule state")
    func testInitialization() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(rule: rule)

        let (ruleId, isEnabled, severity, pendingChanges) = await MainActor.run {
            (viewModel.rule.id, viewModel.isEnabled, viewModel.severity, viewModel.pendingChanges)
        }

        #expect(ruleId == "test_rule")
        #expect(isEnabled == false)
        #expect(severity == nil)
        #expect(pendingChanges == nil)
    }

    @Test("RuleDetailViewModel initializes with opt-in rule")
    func testInitializationOptInRule() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "opt_in_rule", isOptIn: true)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(rule: rule)

        let (isOptIn, isEnabled) = await MainActor.run {
            (viewModel.rule.isOptIn, viewModel.isEnabled)
        }

        #expect(isOptIn == true)
        #expect(isEnabled == false)
    }
}
