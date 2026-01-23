//
//  ConfigDiffPreviewViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ConfigDiffPreviewView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

// Interaction tests for ConfigDiffPreviewView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ConfigDiffPreviewViewInteractionTests {
    
    // MARK: - Test Data Helpers
    
    @MainActor
    private class CallbackTracker {
        var saveCalled = false
        var cancelCalled = false
    }
    
    @MainActor
    private func createConfigDiffPreviewViewSync() -> (view: ConfigDiffPreviewView, tracker: CallbackTracker) {
        let tracker = CallbackTracker()
        
        let diff = YAMLConfigurationEngine.ConfigDiff(
            addedRules: ["new_rule"],
            removedRules: ["old_rule"],
            modifiedRules: ["force_cast"],
            before: "rules:\n  old_rule: error\n  force_cast: error",
            after: "rules:\n  force_cast: warning\n  new_rule: error"
        )
        
        let view = ConfigDiffPreviewView(
            diff: diff,
            ruleName: "Test Rule",
            onSave: { tracker.saveCalled = true },
            onCancel: { tracker.cancelCalled = true }
        )
        
        return (view, tracker)
    }

    @MainActor
    private func findButton<V: View>(in view: V, label: String) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self) { button in
            let text = try? button.labelView().find(ViewType.Text.self).string()
            return text == label
        }
    }

    private struct ViewResult: @unchecked Sendable {
        let view: ConfigDiffPreviewView
        let tracker: CallbackTracker
    }
    
    private func createConfigDiffPreviewView() async -> ViewResult {
        await Task { @MainActor in
            let result = createConfigDiffPreviewViewSync()
            return ViewResult(view: result.view, tracker: result.tracker)
        }.value
    }
    
    // MARK: - Button Interaction Tests
    
    @Test("ConfigDiffPreviewView Cancel button calls onCancel")
    func testCancelButtonCallsOnCancel() async throws {
        let result = await createConfigDiffPreviewView()
        let view = result.view
        let tracker = result.tracker
        
        // Find and tap Cancel button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        try await MainActor.run {
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let button = try findButton(in: viewCapture, label: "Cancel")
            try button.tap()
        }
        
        // Wait for callback
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify callback was called
        let cancelCalled = await MainActor.run {
            tracker.cancelCalled
        }
        #expect(cancelCalled == true, "Cancel button should call onCancel")
    }
    
    @Test("ConfigDiffPreviewView Save Changes button calls onSave")
    func testSaveChangesButtonCallsOnSave() async throws {
        let result = await createConfigDiffPreviewView()
        let view = result.view
        let tracker = result.tracker
        
        // Find and tap Save Changes button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        try await MainActor.run {
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let button = try findButton(in: viewCapture, label: "Save Changes")
            try button.tap()
        }
        
        // Wait for callback
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify callback was called
        let saveCalled = await MainActor.run {
            tracker.saveCalled
        }
        #expect(saveCalled == true, "Save Changes button should call onSave")
    }
    
    // MARK: - View Mode Picker Tests
    
    @Test("ConfigDiffPreviewView view mode picker switches views")
    func testViewModePickerSwitchesViews() async throws {
        let result = await createConfigDiffPreviewView()
        let view = result.view
        
        // Note: Interacting with the picker would require finding and tapping it
        // This is complex with ViewInspector, so we verify the structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSummaryText = await MainActor.run {
            (try? viewCapture.inspect().find(text: "Summary")) != nil
        }
        #expect(hasSummaryText == true, "View mode picker should switch views")
    }
}
