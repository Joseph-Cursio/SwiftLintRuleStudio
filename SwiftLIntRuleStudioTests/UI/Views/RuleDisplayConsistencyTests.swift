//
//  RuleDisplayConsistencyTests.swift
//  SwiftLintRuleStudioTests
//
//  Created for testing display inconsistencies between list and detail views
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

/// Tests to identify display inconsistencies between RuleListItem and RuleDetailView
/// 
/// ViewInspector is already added as a Swift Package dependency.
/// Run these tests to identify inconsistencies in the UI.
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct RuleDisplayConsistencyTests {
    
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
    
    // Helper to create RuleDetailView with environment objects
    // Workaround for Swift 6 strict concurrency: Keep helper @MainActor
    // because 'AnyView' cannot be returned from Task.value (requires Sendable)
    @MainActor
    private func createRuleDetailView(rule: Rule) -> AnyView {
        let container = DependencyContainer.createForTesting()
        return AnyView(RuleDetailView(rule: rule)
            .environmentObject(container))
    }
    
    // Synchronous version for use within MainActor.run blocks
    @MainActor
    private func createRuleDetailViewSync(rule: Rule) -> AnyView {
        let container = DependencyContainer.createForTesting()
        let view = AnyView(RuleDetailView(rule: rule)
            .environmentObject(container))
        nonisolated(unsafe) let viewCapture = view
        return viewCapture
    }
    
    // MARK: - Enabled State Consistency Tests
    
    @Test("RuleListItem shows enabled state")
    func testRuleListItemShowsEnabledState() async throws {
        let enabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        let view = await MainActor.run {
            RuleListItem(rule: enabledRule)
        }
        
        // Inspect the view to find the enabled label
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasEnabledLabel = await MainActor.run {
            (try? viewCapture.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
        }
        #expect(hasEnabledLabel == true, "RuleListItem should show 'Enabled' label for enabled rules")
    }
    
    @Test("RuleListItem hides enabled state for disabled rules")
    func testRuleListItemHidesEnabledStateForDisabledRules() async throws {
        let disabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: false)
        let view = await MainActor.run {
            RuleListItem(rule: disabledRule)
        }
        
        // Try to find the enabled label - it should not exist
        let foundEnabled = await MainActor.run {
            (try? view.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
        }
        #expect(foundEnabled == false, "RuleListItem should not show 'Enabled' label for disabled rules")
    }
    
    @Test("RuleDetailView shows enabled state")
    func testRuleDetailViewShowsEnabledState() async throws {
        let enabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        
        // Inspect the view to find the enabled label in the header
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasEnabledLabel = await MainActor.run {
            let view = createRuleDetailView(rule: enabledRule)
            return (try? view.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
        }
        #expect(hasEnabledLabel == true, "RuleDetailView should show 'Enabled' label for enabled rules")
    }
    
    @Test("RuleDetailView toggle matches enabled state")
    func testRuleDetailViewToggleMatchesEnabledState() async throws {
        let enabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        
        // Find the toggle in the toolbar
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let isOn = try await MainActor.run {
            let view = createRuleDetailView(rule: enabledRule)
            let toggle = try view.inspect().find(ViewType.Toggle.self)
            return try toggle.isOn()
        }
        #expect(isOn == true, "RuleDetailView toggle should be ON for enabled rules")
    }
    
    // MARK: - Consistency Between Views Tests
    
    @Test("Enabled state is consistent between list and detail views")
    func testEnabledStateConsistencyBetweenListAndDetail() async throws {
        // Test with enabled rule
        let enabledRule = await makeTestRule(id: "duplicate_imports", name: "Duplicate Imports", isEnabled: true)
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let (listShowsEnabled, detailShowsEnabled, toggleIsOn) = try await MainActor.run {
            let listView = RuleListItem(rule: enabledRule)
            let detailView = createRuleDetailViewSync(rule: enabledRule)
            
            let listShowsEnabled = (try? listView.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
            
            let detailShowsEnabled = (try? detailView.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
            
            let toggle = try detailView.inspect().find(ViewType.Toggle.self)
            let toggleIsOn = try toggle.isOn()
            
            return (listShowsEnabled, detailShowsEnabled, toggleIsOn)
        }
        
        #expect(listShowsEnabled == true, "List view should show enabled state")
        #expect(detailShowsEnabled == true, "Detail view should show enabled state")
        #expect(toggleIsOn == true, "Detail view toggle should match enabled state")
    }
    
    @Test("Disabled state is consistent between list and detail views")
    func testDisabledStateConsistencyBetweenListAndDetail() async throws {
        // Test with disabled rule
        let disabledRule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: false)
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let (listShowsEnabled, toggleIsOn) = try await MainActor.run {
            let listView = RuleListItem(rule: disabledRule)
            let detailView = createRuleDetailViewSync(rule: disabledRule)
            
            let listShowsEnabled = (try? listView.inspect().find(ViewType.Text.self, where: { view in
                try view.string() == "Enabled"
            })) != nil
            
            let toggle = try detailView.inspect().find(ViewType.Toggle.self)
            let toggleIsOn = try toggle.isOn()
            
            return (listShowsEnabled, toggleIsOn)
        }
        
        #expect(listShowsEnabled == false, "List view should not show enabled state for disabled rules")
        #expect(toggleIsOn == false, "Detail view toggle should be OFF for disabled rules")
    }
    
    // MARK: - Specific Rule Tests
    
    @Test("Duplicate imports rule shows consistent state")
    func testDuplicateImportsRuleConsistency() async throws {
        // Create a rule matching the reported issue
        let duplicateImportsRule = await makeTestRule(
            id: "duplicate_imports",
            name: "Duplicate Imports",
            isEnabled: true
        )
        
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let (listShowsEnabled, detailShowsEnabled, toggleIsOn) = try await MainActor.run {
            let listView = RuleListItem(rule: duplicateImportsRule)
            let detailView = createRuleDetailViewSync(rule: duplicateImportsRule)
            
            let listShowsEnabled = (try? listView.inspect().find(text: "Enabled")) != nil
            let detailShowsEnabled = (try? detailView.inspect().find(text: "Enabled")) != nil
            
            let toggle = try detailView.inspect().find(ViewType.Toggle.self)
            let toggleIsOn = try toggle.isOn()
            
            return (listShowsEnabled, detailShowsEnabled, toggleIsOn)
        }
        
        #expect(listShowsEnabled == true, "duplicate_imports should show as enabled in list")
        #expect(detailShowsEnabled == true, "duplicate_imports should show as enabled in detail header")
        #expect(toggleIsOn == true, "duplicate_imports toggle should be ON")
    }
    
    // MARK: - State Synchronization Tests
    
    @Test("RuleDetailView syncs state on appear")
    func testDetailViewSyncsOnAppear() async throws {
        var rule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: false)
        
        // Initially toggle should be off
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        var toggleIsOn = try await MainActor.run {
            let view = createRuleDetailView(rule: rule)
            let toggle = try view.inspect().find(ViewType.Toggle.self)
            return try toggle.isOn()
        }
        #expect(toggleIsOn == false, "Toggle should start as OFF")
        
        // Update rule to enabled
        rule = await makeTestRule(id: "test_rule", name: "Test Rule", isEnabled: true)
        
        // After creating new view with updated rule, toggle should sync
        // Note: This tests that init properly sets the state
        toggleIsOn = try await MainActor.run {
            let updatedView = createRuleDetailView(rule: rule)
            let toggle = try updatedView.inspect().find(ViewType.Toggle.self)
            return try toggle.isOn()
        }
        #expect(toggleIsOn == true, "Toggle should sync to rule's enabled state")
    }
    
    // MARK: - Helper Methods
    
    private func findEnabledLabel(in view: InspectableView<ViewType.View<RuleListItem>>) -> Bool {
        do {
            _ = try view.find(ViewType.Text.self, where: { textView in
                try textView.string() == "Enabled"
            })
            return true
        } catch {
            return false
        }
    }
}

// MARK: - ViewInspector Extensions

extension RuleListItem: Inspectable {}
extension RuleDetailView: Inspectable {}

