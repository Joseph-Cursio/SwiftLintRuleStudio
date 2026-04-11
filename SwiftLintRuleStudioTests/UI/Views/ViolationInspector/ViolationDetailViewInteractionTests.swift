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
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// Interaction tests for ViolationDetailView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@MainActor
struct ViolationDetailViewInteractionTests {

    // MARK: - Test Data Helpers

    func makeTestViolation(
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
            detectedAt: Date.now,
            resolvedAt: resolvedAt,
            suppressed: suppressed
        )
    }

    // Workaround type to bypass Sendable check for SwiftUI views
    @MainActor
    struct ViewResult: @unchecked Sendable {
        let view: AnyView

        init(view: some View) {
            self.view = AnyView(view)
        }
    }

    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of 'some View'
    @MainActor
    func createViolationDetailView(
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
        .environment(\.dependencies, container)

        return ViewResult(view: view)
    }

    func waitForCondition(
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
    func findButton<V: View>(in view: V, label: String) throws -> InspectableView<ViewType.Button> {
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
            @MainActor
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
            @MainActor
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

}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
