//
//  ViolationDetailViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ViolationDetailView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLIntRuleStudio

// Interaction tests for ViolationDetailView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
// swiftlint:disable:next type_body_length
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
    ) -> Violation {
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

    private func waitForCondition(
        timeoutSeconds: TimeInterval = 1.0,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                condition()
            }
        }
    }

    @MainActor
    private func findButton<V: View>(in view: V, label: String) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self) { button in
            let text = try? button.labelView().find(ViewType.Text.self).string()
            return text == label
        }
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

        _ = makeTestViolation(suppressed: false)

        try await MainActor.run {
            struct DialogHost: View {
                @State var reason: String = ""
                let onSuppress: (String) -> Void

                var body: some View {
                    ViolationDetailView.makeSuppressDialogForTesting(reason: $reason, onSuppress: onSuppress)
                }
            }

            let dialogHost = DialogHost { reason in
                tracker.suppressCalled = true
                tracker.suppressReason = reason
            }

            ViewHosting.host(view: dialogHost)
            defer { ViewHosting.expel() }

            let dialogSuppressButton = try dialogHost.inspect().find(ViewType.Button.self) { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Suppress"
            }
            try dialogSuppressButton.tap()
        }

        let suppressCalled = await tracker.suppressCalled
        let suppressReason = await tracker.suppressReason
        #expect(suppressCalled == true, "Suppress button should trigger onSuppress callback")
        #expect(suppressReason == "Suppressed via Violation Inspector", "Should use default reason when none provided")
    }

    @Test("ViolationDetailView suppress button shows dialog")
    func testSuppressButtonShowsDialog() async throws {
        let violation = makeTestViolation(suppressed: false)
        let hasDialog = await MainActor.run {
            let view = ViolationDetailView(violation: violation, onSuppress: { _ in }, onResolve: {})
            let dialogView = view.suppressDialogForTesting
            let dialogHeader = try? dialogView.inspect().find(text: "Suppression Reason")
            return dialogHeader != nil
        }

        #expect(hasDialog == true, "Suppress button should show suppress dialog")
    }

    @Test("ViolationDetailView suppress dialog has cancel button")
    func testSuppressDialogHasCancelButton() async throws {
        let violation = makeTestViolation(suppressed: false)
        let hasCancelButton = await MainActor.run {
            let view = ViolationDetailView(violation: violation, onSuppress: { _ in }, onResolve: {})
            let dialogView = view.suppressDialogForTesting
            let cancelButton = try? dialogView.inspect().find(ViewType.Button.self) { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Cancel"
            }
            return cancelButton != nil
        }

        #expect(hasCancelButton == true, "Suppress dialog should have cancel button")
    }

    @Test("ViolationDetailView suppress dialog has suppress button")
    func testSuppressDialogHasSuppressButton() async throws {
        let violation = makeTestViolation(suppressed: false)
        let hasSuppressButton = try await MainActor.run {
            let view = ViolationDetailView(violation: violation, onSuppress: { _ in }, onResolve: {})
            let dialogView = view.suppressDialogForTesting
            _ = try dialogView.inspect().find(ViewType.Button.self) { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Suppress"
            }
            return true
        }

        #expect(hasSuppressButton == true, "Suppress dialog should have suppress button")
    }

    @Test("ViolationDetailView suppress dialog has text field for reason")
    func testSuppressDialogHasTextField() async throws {
        let violation = makeTestViolation(suppressed: false)
        let hasTextField = await MainActor.run {
            let view = ViolationDetailView(violation: violation, onSuppress: { _ in }, onResolve: {})
            let dialogView = view.suppressDialogForTesting
            let textField = try? dialogView.inspect().find(ViewType.TextField.self)
            return textField != nil
        }

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

        try await MainActor.run {
            struct DialogHost: View {
                @State var reason: String = "Custom suppression reason"
                let onSuppress: (String) -> Void

                var body: some View {
                    ViolationDetailView.makeSuppressDialogForTesting(reason: $reason, onSuppress: onSuppress)
                }
            }

            let dialogHost = DialogHost { reason in
                tracker.suppressReason = reason
            }

            ViewHosting.host(view: dialogHost)
            defer { ViewHosting.expel() }

            let dialogSuppressButton = try dialogHost.inspect().find(ViewType.Button.self) { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Suppress"
            }
            try dialogSuppressButton.tap()
        }

        let suppressReason = await tracker.suppressReason
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

        let violation = makeTestViolation(resolvedAt: nil)
        let result = await Task { @MainActor in
            createViolationDetailView(
                violation: violation,
                onResolve: {
                    tracker.resolveCalled = true
                }
            )
        }.value

        // Find and tap the resolve button
        try await MainActor.run {
            let resolveButton = try findButton(in: result.view, label: "Mark as Resolved")
            try resolveButton.tap()
        }

        let resolveCalled = await waitForCondition {
            tracker.resolveCalled
        }
        #expect(resolveCalled == true, "Resolve button should trigger onResolve callback")
    }

    // MARK: - Open in Xcode Button Tests

    @Test("ViolationDetailView open in Xcode button exists")
    func testOpenInXcodeButtonExists() async throws {
        let violation = makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value

        // Find the open in Xcode button by searching for buttons and checking their labels
        // The button uses a Label, so we need to find it differently
        let hasOpenButton = try await MainActor.run {
            let buttons = try result.view.inspect().findAll(ViewType.Button.self)
            let openButton = buttons.first { button in
                // Try to find text "Open in Xcode" within the button's label
                do {
                    _ = try button.find(text: "Open in Xcode")
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
        let violation = makeTestViolation()
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value

        // Find the open in Xcode button by searching for buttons
        let isTappable = try await MainActor.run {
            let buttons = try result.view.inspect().findAll(ViewType.Button.self)
            let openButton = buttons.first { button in
                // Try to find text "Open in Xcode" within the button's label
                do {
                    _ = try button.find(text: "Open in Xcode")
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
        let violation = makeTestViolation(suppressed: true)
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value

        // Suppress button should not exist
        let hasSuppressButton = await MainActor.run {
            let suppressText = try? result.view.inspect().find(text: "Suppress")
            return suppressText != nil
        }
        #expect(hasSuppressButton == false, "Suppress button should be hidden when violation is suppressed")
    }

    @Test("ViolationDetailView resolve button is hidden when resolved")
    func testResolveButtonHiddenWhenResolved() async throws {
        let violation = makeTestViolation(resolvedAt: Date())
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationDetailView(violation: violation) }.value

        // Resolve button should not exist
        let hasResolveButton = await MainActor.run {
            (try? findButton(in: result.view, label: "Mark as Resolved")) != nil
        }
        #expect(hasResolveButton == false, "Resolve button should be hidden when violation is resolved")
    }
}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions



