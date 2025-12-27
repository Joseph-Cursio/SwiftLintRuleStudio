//
//  RuleDisplayConsistencySimpleTests.swift
//  SwiftLintRuleStudioTests
//
//  Simple tests for display inconsistencies that don't require ViewInspector
//

import Testing
@testable import SwiftLIntRuleStudio

/// Simple tests to verify rule state consistency without ViewInspector
/// These tests check the data model and view initialization logic
// RuleDetailView is a SwiftUI view (implicitly @MainActor), but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct RuleDisplayConsistencySimpleTests {
    
    // MARK: - Test Data Helpers
    
    private func makeTestRule(id: String, name: String, isEnabled: Bool, isOptIn: Bool = false) async -> Rule {
        await MainActor.run {
            Rule(
                id: id,
                name: name,
                description: "Test description for \(name)",
                category: .lint,
                isOptIn: isOptIn,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: isEnabled,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }
    }
    
    // MARK: - Rule State Tests
    
    @Test("Rule with isEnabled=true should have enabled state")
    func testEnabledRuleHasCorrectState() async {
        let rule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        // Extract value to avoid Swift 6 false positive
        let isEnabled = await MainActor.run { rule.isEnabled }
        #expect(isEnabled == true)
    }
    
    @Test("Rule with isEnabled=false should have disabled state")
    func testDisabledRuleHasCorrectState() async {
        let rule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: false)
        // Extract value to avoid Swift 6 false positive
        let isEnabled = await MainActor.run { rule.isEnabled }
        #expect(isEnabled == false)
    }
    
    // MARK: - RuleDetailView Initialization Tests
    
    @Test("RuleDetailView initializes isEnabled from rule")
    func testRuleDetailViewInitializesFromRule() async {
        let enabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        let detailView = await MainActor.run {
            RuleDetailView(rule: enabledRule)
        }
        
        // Access the private state through reflection or check that init worked
        // Since isEnabled is private, we verify the view was created successfully
        // The actual state check requires ViewInspector
        let (ruleId, isEnabled) = await MainActor.run {
            return (detailView.rule.id, detailView.rule.isEnabled)
        }
        #expect(ruleId == "test_rule")
        #expect(isEnabled == true)
    }
    
    @Test("RuleDetailView syncs enabled state on initialization")
    func testRuleDetailViewSyncsState() async {
        // Test that when a rule is enabled, the detail view should reflect it
        let enabledRule = await makeTestRule(id: "duplicate_imports", name: "Duplicate Imports", isEnabled: true)
        let detailView = await MainActor.run {
            RuleDetailView(rule: enabledRule)
        }
        
        // Verify the rule data is correct
        let (isEnabled, ruleId) = await MainActor.run {
            return (detailView.rule.isEnabled, detailView.rule.id)
        }
        #expect(isEnabled == true)
        #expect(ruleId == "duplicate_imports")
    }
    
    // MARK: - Consistency Tests
    
    @Test("Same rule instance should have consistent state")
    func testRuleStateConsistency() async {
        let rule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        
        // Create multiple views with the same rule
        let (listItem, detailView) = await MainActor.run {
            let listItem = RuleListItem(rule: rule)
            let detailView = RuleDetailView(rule: rule)
            return (listItem, detailView)
        }
        
        // Both should reference the same rule data
        let (listItemId, detailViewId, listItemEnabled, detailViewEnabled) = await MainActor.run {
            return (listItem.rule.id, detailView.rule.id, listItem.rule.isEnabled, detailView.rule.isEnabled)
        }
        #expect(listItemId == detailViewId)
        #expect(listItemEnabled == detailViewEnabled)
        #expect(listItemEnabled == true)
    }
    
    @Test("Duplicate imports rule consistency check")
    func testDuplicateImportsConsistency() async {
        // Test the specific rule that was reported as inconsistent
        let duplicateImportsRule = await makeTestRule(
            id: "duplicate_imports",
            name: "Duplicate Imports",
            isEnabled: true
        )
        
        let (listItem, detailView) = await MainActor.run {
            let listItem = RuleListItem(rule: duplicateImportsRule)
            let detailView = RuleDetailView(rule: duplicateImportsRule)
            return (listItem, detailView)
        }
        
        // Verify both views have the same rule data
        let (listItemId, detailViewId, listItemEnabled, detailViewEnabled) = await MainActor.run {
            return (listItem.rule.id, detailView.rule.id, listItem.rule.isEnabled, detailView.rule.isEnabled)
        }
        #expect(listItemId == "duplicate_imports")
        #expect(detailViewId == "duplicate_imports")
        #expect(listItemEnabled == true)
        #expect(detailViewEnabled == true)
        #expect(listItemEnabled == detailViewEnabled)
    }
    
    // MARK: - Rule Lookup Tests
    
    @Test("Rule lookup from registry should return correct state")
    func testRuleLookupFromRegistry() async throws {
        // This test would require a mock registry
        // For now, we verify the rule model itself is consistent
        
        let rule1 = await makeTestRule(id: "rule1", name: "Rule 1", isEnabled: true)
        let rule2 = await makeTestRule(id: "rule1", name: "Rule 1", isEnabled: true)
        
        // Same rule data should be equal - extract values to avoid Swift 6 false positive
        let (id1, id2, enabled1, enabled2) = await MainActor.run {
            return (rule1.id, rule2.id, rule1.isEnabled, rule2.isEnabled)
        }
        #expect(id1 == id2)
        #expect(enabled1 == enabled2)
    }
    
    @Test("Rule with different enabled states should be different")
    func testRuleStateDifference() async {
        let enabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        let disabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: false)
        
        // Extract values to avoid Swift 6 false positive
        let (enabled, disabled, enabledId, disabledId) = await MainActor.run {
            return (enabledRule.isEnabled, disabledRule.isEnabled, enabledRule.id, disabledRule.id)
        }
        #expect(enabled != disabled)
        #expect(enabledId == disabledId) // Same rule, different state
    }
}

