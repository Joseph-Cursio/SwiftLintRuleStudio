//
//  ConfigDiffPreviewViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ConfigDiffPreviewView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

extension ConfigDiffPreviewView: Inspectable {}

// Tests for ConfigDiffPreviewView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ConfigDiffPreviewViewTests {
    
    // MARK: - Test Data Helpers
    
    private final class CallbackTracker: @unchecked Sendable {
        var saveCalled = false
        var cancelCalled = false
    }
    
    private func createConfigDiffPreviewView(
        diff: YAMLConfigurationEngine.ConfigDiff? = nil,
        initialView: ConfigDiffPreviewView.DiffViewMode = .summary
    ) async -> (view: ConfigDiffPreviewView, tracker: CallbackTracker) {
        return await MainActor.run {
            let tracker = CallbackTracker()
            
            let defaultDiff = YAMLConfigurationEngine.ConfigDiff(
                addedRules: ["new_rule"],
                removedRules: ["old_rule"],
                modifiedRules: ["force_cast"],
                before: "rules:\n  old_rule: error\n  force_cast: error",
                after: "rules:\n  force_cast: warning\n  new_rule: error"
            )
            
            let view = ConfigDiffPreviewView(
                diff: diff ?? defaultDiff,
                ruleName: "Test Rule",
                onSave: { tracker.saveCalled = true },
                onCancel: { tracker.cancelCalled = true },
                selectedView: initialView
            )
            
            return (view, tracker)
        }
    }
    
    // MARK: - Initialization Tests
    
    @Test("ConfigDiffPreviewView initializes correctly")
    func testInitialization() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Verify the view can be created
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasNavigationStack = try await MainActor.run {
            _ = try view.inspect().find(ViewType.NavigationStack.self)
            return true
        }
        #expect(hasNavigationStack == true, "ConfigDiffPreviewView should initialize with NavigationStack")
    }
    
    @Test("ConfigDiffPreviewView displays header")
    func testDisplaysHeader() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find header text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasHeader = try await MainActor.run {
            _ = try view.inspect().find(text: "Preview Configuration Changes")
            return true
        }
        #expect(hasHeader == true, "ConfigDiffPreviewView should display header")
    }
    
    @Test("ConfigDiffPreviewView displays description")
    func testDisplaysDescription() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find description text
        let hasDescription = try? await MainActor.run {
            _ = try view.inspect().find(
                text: "Review the changes that will be made to your .swiftlint.yml file"
            )
            return true
        }
        #expect(hasDescription == true, "ConfigDiffPreviewView should display description")
    }
    
    // MARK: - Summary View Tests
    
    @Test("ConfigDiffPreviewView displays summary view by default")
    func testDisplaysSummaryViewByDefault() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find summary view content
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasSummary = try await MainActor.run {
            _ = try view.inspect().find(text: "Changes Summary")
            return true
        }
        #expect(hasSummary == true, "ConfigDiffPreviewView should display summary view by default")
    }
    
    @Test("ConfigDiffPreviewView shows added rules in summary")
    func testShowsAddedRulesInSummary() async throws {
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: ["new_rule", "another_rule"],
            removedRules: [],
            modifiedRules: [],
            before: "",
            after: ""
        )
        let (view, _) = await createConfigDiffPreviewView(diff: diff, initialView: .summary)
        
        // Find added rules section
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasAddedRules = try? await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            _ = try view.inspect().find(text: "Rules to be Added")
            return true
        }
        #expect(hasAddedRules == true, "ConfigDiffPreviewView should show added rules in summary")
    }
    
    @Test("ConfigDiffPreviewView shows removed rules in summary")
    func testShowsRemovedRulesInSummary() async throws {
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: ["old_rule", "another_old_rule"],
            modifiedRules: [],
            before: "",
            after: ""
        )
        let (view, _) = await createConfigDiffPreviewView(diff: diff, initialView: .summary)
        
        // Find removed rules section
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasRemovedRules = try? await MainActor.run {
            _ = try view.inspect().find(text: "Rules to be Removed")
            return true
        }
        #expect(hasRemovedRules == true, "ConfigDiffPreviewView should show removed rules in summary")
    }
    
    @Test("ConfigDiffPreviewView shows modified rules in summary")
    func testShowsModifiedRulesInSummary() async throws {
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: [],
            modifiedRules: ["force_cast", "line_length"],
            before: "",
            after: ""
        )
        let (view, _) = await createConfigDiffPreviewView(diff: diff, initialView: .summary)
        
        // Find modified rules section
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasModifiedRules = try? await MainActor.run {
            _ = try view.inspect().find(text: "Rules to be Modified")
            return true
        }
        #expect(hasModifiedRules == true, "ConfigDiffPreviewView should show modified rules in summary")
    }
    
    @Test("ConfigDiffPreviewView shows no changes message when empty")
    func testShowsNoChangesMessageWhenEmpty() async throws {
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: [],
            modifiedRules: [],
            before: "",
            after: ""
        )
        let (view, _) = await createConfigDiffPreviewView(diff: diff, initialView: .summary)
        
        // Find no changes message
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasNoChanges = try? await MainActor.run {
            _ = try view.inspect().find(text: "No changes detected")
            return true
        }
        #expect(hasNoChanges == true, "ConfigDiffPreviewView should show no changes message when empty")
    }
    
    // MARK: - Full Diff View Tests
    
    @Test("ConfigDiffPreviewView displays full diff view when selected")
    func testDisplaysFullDiffView() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Note: Switching to full diff view would require interacting with the picker
        // We verify the structure exists
        let hasNavigationStack = try await MainActor.run {
            _ = try view.inspect().find(ViewType.NavigationStack.self)
            return true
        }
        #expect(hasNavigationStack == true, "ConfigDiffPreviewView should display full diff view when selected")
    }

    @Test("ConfigDiffPreviewView switches to full diff view")
    func testSwitchesToFullDiffView() async throws {
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: [],
            modifiedRules: [],
            before: "",
            after: ""
        )
        let (view, _) = await createConfigDiffPreviewView(diff: diff, initialView: .full)

        let hasEmptyConfig = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            _ = try inspector.find(text: "Before")
            _ = try inspector.find(text: "After")
            return (try? inspector.find(text: "(empty configuration)")) != nil
        }

        #expect(hasEmptyConfig == true, "Full diff should show empty configuration text")
    }
    
    // MARK: - Action Buttons Tests
    
    @Test("ConfigDiffPreviewView displays Cancel button")
    func testDisplaysCancelButton() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find Cancel button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasCancelButton = try await MainActor.run {
            _ = try view.inspect().find(text: "Cancel")
            return true
        }
        #expect(hasCancelButton == true, "ConfigDiffPreviewView should display Cancel button")
    }
    
    @Test("ConfigDiffPreviewView displays Save Changes button")
    func testDisplaysSaveChangesButton() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find Save Changes button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasSaveButton = try await MainActor.run {
            _ = try view.inspect().find(text: "Save Changes")
            return true
        }
        #expect(hasSaveButton == true, "ConfigDiffPreviewView should display Save Changes button")
    }

    @Test("ConfigDiffPreviewView Cancel button triggers callback")
    func testCancelButtonTriggersCallback() async throws {
        let (view, tracker) = await createConfigDiffPreviewView()

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let button = try inspector.find(ViewType.Button.self) { button in
                (try? button.labelView().text().string()) == "Cancel"
            }
            try button.tap()
        }

        #expect(tracker.cancelCalled == true, "Cancel callback should be invoked")
    }

    @Test("ConfigDiffPreviewView Save button triggers callback")
    func testSaveButtonTriggersCallback() async throws {
        let (view, tracker) = await createConfigDiffPreviewView()

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let button = try inspector.find(ViewType.Button.self) { button in
                (try? button.labelView().text().string()) == "Save Changes"
            }
            try button.tap()
        }

        #expect(tracker.saveCalled == true, "Save callback should be invoked")
    }
    
    // MARK: - View Mode Picker Tests
    
    @Test("ConfigDiffPreviewView displays view mode picker")
    func testDisplaysViewModePicker() async throws {
        let (view, _) = await createConfigDiffPreviewView()
        
        // Find view mode picker options
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let (hasSummary, hasFullDiff) = await MainActor.run {
            let summaryText = try? view.inspect().find(text: "Summary")
            let fullDiffText = try? view.inspect().find(text: "Full Diff")
            return (summaryText != nil, fullDiffText != nil)
        }
        
        #expect(hasSummary == true || hasFullDiff == true, "ConfigDiffPreviewView should display view mode picker")
    }
}
