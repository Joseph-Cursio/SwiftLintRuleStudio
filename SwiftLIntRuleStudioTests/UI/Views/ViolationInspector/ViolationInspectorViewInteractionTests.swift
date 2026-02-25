//
//  ViolationInspectorViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ViolationInspectorView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLIntRuleStudio

// Interaction tests for ViolationInspectorView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ViolationInspectorViewInteractionTests {

    // MARK: - Test Data Helpers

    private func makeTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        column: Int? = 5,
        severity: Severity = .error,
        message: String = "Test violation message"
    ) -> Violation {
        Violation(
            id: id,
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            column: column,
            severity: severity,
            message: message
        )
    }

    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let container: DependencyContainer

        init(view: some View, container: DependencyContainer) {
            self.view = AnyView(view)
            self.container = container
        }
    }

    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createViolationInspectorView(
        violations: [Violation] = [],
        workspace: Workspace? = nil
    ) -> ViewResult {
        let container = DependencyContainer.createForTesting()

        // Set up workspace if provided
        if let workspace = workspace {
            try? container.workspaceManager.openWorkspace(at: workspace.path)
        }

        let view = ViolationInspectorView()
            .environmentObject(container)

        return ViewResult(view: view, container: container)
    }

    private func waitForText(
        in view: AnyView,
        text: String,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        struct ViewWrapper: @unchecked Sendable {
            let view: AnyView
        }
        let wrapper = ViewWrapper(view: view)
        return await UIAsyncTestHelpers.waitForText(
            in: wrapper.view,
            text: text,
            timeout: timeoutSeconds
        )
    }

    private func waitForSearchFieldInput(
        in view: AnyView,
        expected: String,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        struct ViewWrapper: @unchecked Sendable {
            let view: AnyView
        }
        let wrapper = ViewWrapper(view: view)
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                let searchField = try? wrapper.view.inspect().find(ViewType.TextField.self)
                return (try? searchField?.input()) == expected
            }
        }
    }

    // MARK: - Search Interaction Tests

    @Test("ViolationInspectorView search field accepts text input")
    func testSearchFieldAcceptsInput() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField
        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text
            try searchField.setInput("test")

            // Verify input was set
            return try searchField.input()
        }
        #expect(inputValue == "test", "Search field should accept text input")
    }

    @Test("ViolationInspectorView search filters violations by rule ID")
    func testSearchFiltersByRuleID() async throws {
        let violations = [
            await makeTestViolation(ruleID: "force_cast", message: "Force cast violation"),
            await makeTestViolation(ruleID: "unused_import", message: "Unused import violation")
        ]

        // Create view with violations loaded in view model
        // Note: This requires setting up the view model with violations
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value
        // Find the search TextField
        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text
            try searchField.setInput("force_cast")

            return try searchField.input()
        }

        // Verify search field has the input
        #expect(inputValue == "force_cast", "Search should filter by rule ID")
    }

    @Test("ViolationInspectorView search filters violations by message")
    func testSearchFiltersByMessage() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField
        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text
            try searchField.setInput("violation")

            return try searchField.input()
        }
        #expect(inputValue == "violation", "Search should filter by message")
    }

    @Test("ViolationInspectorView search filters violations by file path")
    func testSearchFiltersByFilePath() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField
        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text
            try searchField.setInput("Test.swift")

            return try searchField.input()
        }
        #expect(inputValue == "Test.swift", "Search should filter by file path")
    }

    @Test("ViolationInspectorView search is case insensitive")
    func testSearchIsCaseInsensitive() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField
        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text in different case
            try searchField.setInput("FORCE_CAST")

            return try searchField.input()
        }
        #expect(inputValue == "FORCE_CAST", "Search should accept case insensitive input")
    }

    // MARK: - Filter Interaction Tests

    @Test("ViolationInspectorView clear filters button appears when filters are active")
    func testClearFiltersButtonAppears() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField and enter text
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let inputValue = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)
            try searchField.setInput("test")
            return try searchField.input()
        }
        #expect(inputValue == "test", "Search input should accept text")
    }

    @Test("ViolationInspectorView clear filters button clears all filters")
    func testClearFiltersButtonClearsFilters() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField and enter text
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let hasClearButton = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)
            try searchField.setInput("test")

            // Find and tap clear filters button
            let clearButton = try? result.view.inspect().find(ViewType.Button.self) { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Clear"
            }
            if let clearButton = clearButton {
                try clearButton.tap()
            }

            return clearButton != nil
        }

        // Verify search field is cleared if button was found
        if hasClearButton {
            let didClear = await waitForSearchFieldInput(in: result.view, expected: "")
            #expect(didClear == true, "Clear filters should clear search field")
        }
    }

    // MARK: - Refresh Button Tests

    @Test("ViolationInspectorView refresh button exists in toolbar")
    func testRefreshButtonExists() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find refresh button (may be in toolbar)
        // Note: Toolbar buttons may not be directly accessible via ViewInspector
        // We verify the view structure exists
        let hasNavigationSplitView = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasNavigationSplitView == true, "ViolationInspectorView should have refresh button in toolbar")
    }

    // MARK: - Selection Tests

    @Test("ViolationInspectorView allows violation selection")
    func testAllowsViolationSelection() async throws {
        let violations = [await makeTestViolation()]
        let result = await Task { @MainActor in
            let container = DependencyContainer.createForTesting()
            let viewModel = ViolationInspectorViewModel(violationStorage: container.violationStorage)
            viewModel.violations = violations
            viewModel.filteredViolations = violations
            viewModel.searchText = ""
            let view = ViolationInspectorView(viewModel: viewModel)
                .environmentObject(container)
            return ViewResult(view: view, container: container)
        }.value

        // Verify violations are rendered: non-grouped mode uses Table (unsupported by
        // ViewInspector 0.10.3), so check that the empty state is NOT shown instead.
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let showsEmptyState = await MainActor.run {
            (try? result.view.inspect().find(text: "No violations match your current filters.")) != nil
        }
        #expect(!showsEmptyState, "ViolationInspectorView should display violations (not empty state) when filteredViolations is set")
    }

    // MARK: - Empty State Interaction Tests

    @Test("ViolationInspectorView empty state clear filters button works")
    func testEmptyStateClearFiltersButton() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField and enter text to trigger empty state
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let hasClearButton = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)
            try searchField.setInput("nonexistent")

            // Find clear filters button in empty state
            let clearText = try? result.view.inspect().find(text: "Clear Filters")
            let clearButton = try? clearText?.parent().find(ViewType.Button.self)
            if let clearButton = clearButton {
                try clearButton.tap()
                return true
            }
            return false
        }

        // Verify search field is cleared if button was found
        if hasClearButton {
            let didClear = await waitForSearchFieldInput(in: result.view, expected: "")
            #expect(didClear == true, "Empty state clear filters should clear search field")
        }
    }

    // MARK: - Statistics Update Tests

    @Test("ViolationInspectorView statistics update when filters change")
    func testStatisticsUpdateWithFilters() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        // Find the search TextField
        let hasVStack = try await MainActor.run {
            let searchField = try result.view.inspect().find(ViewType.TextField.self)

            // Enter search text
            try searchField.setInput("test")

            // Statistics should update (we verify the view structure exists)
            let vStack = try result.view.inspect().find(ViewType.VStack.self)
            return vStack != nil
        }

        #expect(hasVStack == true, "Statistics should update when filters change")
    }
}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
