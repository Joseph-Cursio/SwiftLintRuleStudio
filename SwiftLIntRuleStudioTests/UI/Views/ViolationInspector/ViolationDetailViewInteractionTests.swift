//
//  ViolationDetailViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ViolationDetailView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

/// Interaction tests for ViolationDetailView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct ViolationDetailViewInteractionTests {
    
    // MARK: - Test Data Helpers
    
    private func makeTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        column: Int? = 5,
        severity: Severity = .error,
        message: String = "Test violation message",
        suppressed: Bool = false,
        resolvedAt: Date? = nil
    ) async -> Violation {
        await MainActor.run {
            Violation(
                id: id,
                ruleID: ruleID,
                filePath: filePath,
                line: line,
                column: column,
                severity: severity,
                message: message,
                detectedAt: Date(),
                resolvedAt: resolvedAt,
                suppressed: suppressed
            )
        }
    }
    
    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        
        init(view: some View) {
            self.view = AnyView(view)
        }
    }
    
    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of 'some View'
    @MainActor
    private func createViolationDetailView(
        violation: Violation,
        onSuppress: @escaping (String) -> Void = { _ in },
        onResolve: @escaping () -> Void = {}
    ) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = ViolationDetailView(
            violation: violation,
            onSuppress: onSuppress,
            onResolve: onResolve
        )
        .environmentObject(container)
        
        return ViewResult(view: view)
    }
    
    // MARK: - Suppress Button Interaction Tests
    
    @Test("ViolationDetailView suppress button triggers onSuppress callback")
    func testSuppressButtonTriggersCallback() async throws {
        // Use a @MainActor class to collect callback updates (callbacks run on MainActor)
        @MainActor
        class CallbackTracker {
            var suppressCalled = false
            var suppressReason: String?
        }
        let tracker = await MainActor.run { CallbackTracker() }
        
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        nonisolated(unsafe) let trackerCapture = tracker
        let result = await Task { @MainActor in
            createViolationDetailView(
                violation: violation,
                onSuppress: { reason in
                    trackerCapture.suppressCalled = true
                    trackerCapture.suppressReason = reason
                }
            )
        }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
        }
        
        // Wait a bit for async callback
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let suppressCalled = await trackerCapture.suppressCalled
        let suppressReason = await trackerCapture.suppressReason
        #expect(suppressCalled == true, "Suppress button should trigger onSuppress callback")
        #expect(suppressReason == "Suppressed via Violation Inspector", "Should use default reason when none provided")
    }
    
    @Test("ViolationDetailView suppress button shows dialog")
    func testSuppressButtonShowsDialog() async throws {
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasDialog = try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
            
            // Find the suppress dialog
            let dialogTitle = try? viewCapture.inspect().find(text: "Suppress Violation")
            return dialogTitle != nil
        }
        
        // Wait for dialog to appear
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(hasDialog == true, "Suppress button should show suppress dialog")
    }
    
    @Test("ViolationDetailView suppress dialog has cancel button")
    func testSuppressDialogHasCancelButton() async throws {
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasCancelButton = try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
            
            // Find cancel button
            let cancelText = try? viewCapture.inspect().find(text: "Cancel")
            let cancelButton = try? cancelText?.parent().find(ViewType.Button.self)
            return cancelButton != nil
        }
        
        // Wait for dialog to appear
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(hasCancelButton == true, "Suppress dialog should have cancel button")
    }
    
    @Test("ViolationDetailView suppress dialog has suppress button")
    func testSuppressDialogHasSuppressButton() async throws {
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppressButton = try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
            
            // Find suppress button in dialog (there may be multiple, so we check for existence)
            let dialogSuppressText = try? viewCapture.inspect().find(text: "Suppress")
            let dialogSuppressButton = try? dialogSuppressText?.parent().find(ViewType.Button.self)
            return dialogSuppressButton != nil
        }
        
        // Wait for dialog to appear
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(hasSuppressButton == true, "Suppress dialog should have suppress button")
    }
    
    @Test("ViolationDetailView suppress dialog has text field for reason")
    func testSuppressDialogHasTextField() async throws {
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasTextField = try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
            
            // Find text field
            let textField = try? viewCapture.inspect().find(ViewType.TextField.self)
            return textField != nil
        }
        
        // Wait for dialog to appear
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(hasTextField == true, "Suppress dialog should have text field for reason")
    }
    
    @Test("ViolationDetailView suppress dialog passes custom reason")
    func testSuppressDialogPassesCustomReason() async throws {
        // Use a @MainActor class to collect callback updates (callbacks run on MainActor)
        @MainActor
        class CallbackTracker {
            var suppressReason: String?
        }
        let tracker = await MainActor.run { CallbackTracker() }
        
        let violation = await makeTestViolation(suppressed: false)
        // Workaround: Use ViewResult to bypass Sendable check
        nonisolated(unsafe) let trackerCapture = tracker
        let result = await Task { @MainActor in
            createViolationDetailView(
                violation: violation,
                onSuppress: { reason in
                    trackerCapture.suppressReason = reason
                }
            )
        }.value
        let view = result.view
        
        // Find and tap the suppress button by finding text and then button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        try await MainActor.run {
            let suppressText = try viewCapture.inspect().find(text: "Suppress")
            let suppressButton = try suppressText.parent().find(ViewType.Button.self)
            try suppressButton.tap()
        }
        
        // Wait for dialog to appear
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Enter custom reason in text field
        try await MainActor.run {
            let textField = try viewCapture.inspect().find(ViewType.TextField.self)
            try textField.setInput("Custom suppression reason")
            
            // Find and tap the suppress button in dialog
            let dialogSuppressText = try viewCapture.inspect().find(text: "Suppress")
            let dialogSuppressButton = try dialogSuppressText.parent().find(ViewType.Button.self)
            try dialogSuppressButton.tap()
        }
        
        // Wait for callback
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let suppressReason = await trackerCapture.suppressReason
        #expect(suppressReason == "Custom suppression reason", "Should pass custom reason from dialog")
    }
    
    // MARK: - Resolve Button Interaction Tests
    
    @Test("ViolationDetailView resolve button triggers onResolve callback")
    func testResolveButtonTriggersCallback() async throws {
        // Use a @MainActor class to collect callback updates (callbacks run on MainActor)
        @MainActor
        class CallbackTracker {
            var resolveCalled = false
        }
        let tracker = await MainActor.run { CallbackTracker() }
        
        let violation = await makeTestViolation(resolvedAt: nil)
        // Workaround: Use ViewResult to bypass Sendable check
        nonisolated(unsafe) let trackerCapture = tracker
        let result = await Task { @MainActor in
            createViolationDetailView(
                violation: violation,
                onResolve: {
                    trackerCapture.resolveCalled = true
                }
            )
        }.value
        let view = result.view
        
        // Find and tap the resolve button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        try await MainActor.run {
            let resolveText = try viewCapture.inspect().find(text: "Mark as Resolved")
            let resolveButton = try resolveText.parent().find(ViewType.Button.self)
            try resolveButton.tap()
        }
        
        // Wait a bit for async callback
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let resolveCalled = await trackerCapture.resolveCalled
        #expect(resolveCalled == true, "Resolve button should trigger onResolve callback")
    }
    
    // MARK: - Open in Xcode Button Tests
    
    @Test("ViolationDetailView open in Xcode button exists")
    func testOpenInXcodeButtonExists() async throws {
        let violation = await makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find the open in Xcode button by searching for buttons and checking their labels
        // The button uses a Label, so we need to find it differently
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasOpenButton = try await MainActor.run {
            let buttons = try viewCapture.inspect().findAll(ViewType.Button.self)
            let openButton = try buttons.first { button in
                // Try to find text "Open in Xcode" within the button's label
                do {
                    let _ = try button.find(text: "Open in Xcode")
                    return true
                } catch {
                    return false
                }
            }
            return openButton != nil
        }
        #expect(hasOpenButton == true, "ViolationDetailView should have 'Open in Xcode' button")
    }
    
    @Test("ViolationDetailView open in Xcode button is tappable")
    func testOpenInXcodeButtonIsTappable() async throws {
        let violation = await makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Find the open in Xcode button by searching for buttons
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let isTappable = try await MainActor.run {
            let buttons = try viewCapture.inspect().findAll(ViewType.Button.self)
            let openButton = try buttons.first { button in
                // Try to find text "Open in Xcode" within the button's label
                do {
                    let _ = try button.find(text: "Open in Xcode")
                    return true
                } catch {
                    return false
                }
            }
            
            guard let openButton = openButton else {
                return false
            }
            
            // Button should be tappable (no crash)
            try openButton.tap()
            return true
        }
        #expect(isTappable == true, "Open in Xcode button should be tappable")
    }
    
    // MARK: - Button Visibility Tests
    
    @Test("ViolationDetailView suppress button is hidden when suppressed")
    func testSuppressButtonHiddenWhenSuppressed() async throws {
        let violation = await makeTestViolation(suppressed: true)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Suppress button should not exist
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasSuppressButton = await MainActor.run {
            let suppressText = try? viewCapture.inspect().find(text: "Suppress")
            return suppressText != nil
        }
        #expect(hasSuppressButton == false, "Suppress button should be hidden when violation is suppressed")
    }
    
    @Test("ViolationDetailView resolve button is hidden when resolved")
    func testResolveButtonHiddenWhenResolved() async throws {
        let violation = await makeTestViolation(resolvedAt: Date())
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value
        let view = result.view
        
        // Resolve button should not exist
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasResolveButton = await MainActor.run {
            let resolveText = try? viewCapture.inspect().find(text: "Mark as Resolved")
            return resolveText != nil
        }
        #expect(hasResolveButton == false, "Resolve button should be hidden when violation is resolved")
    }
}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions

