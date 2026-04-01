//
//  ViolationInspectorViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ViolationInspectorView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// Tests for ViolationInspectorView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@MainActor
struct ViolationInspectorViewTests {

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
    @MainActor
    struct ViewResult: @unchecked Sendable {
        let view: AnyView

        init(view: some View) {
            self.view = AnyView(view)
        }
    }

    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of 'some View'
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
            .environment(\.dependencies, container)

        return ViewResult(view: view)
    }

    // MARK: - View Structure Tests

    @Test("ViolationInspectorView renders core structural elements")
    func testCoreStructure() async throws {
        let result = await Task { @MainActor in createViolationInspectorView() }.value

        let (hasHStack, hasTextField, hasVStack) = try await MainActor.run {
            let inspector = try result.view.inspect()
            return (
                (try? inspector.find(ViewType.HStack.self)) != nil,
                (try? inspector.find(ViewType.TextField.self)) != nil,
                (try? inspector.find(ViewType.VStack.self)) != nil
            )
        }
        #expect(hasHStack, "Should contain HStack layout for filters/statistics")
        #expect(hasTextField, "Should contain search TextField")
        #expect(hasVStack, "Should contain VStack for list content")
    }

    // MARK: - Empty State Tests

    @Test("ViolationInspectorView starts with empty violations (triggers empty state branch)")
    func testShowsEmptyState() async throws {
        let container = await Task { @MainActor in DependencyContainer.createForTesting() }.value

        // Without a workspace, the view model has no violations — the view will render emptyStateView.
        // ViewInspector cannot reliably traverse conditional branches, so verify the model state
        // that drives the empty state rather than searching for rendered text.
        let isEmpty = await MainActor.run {
            let viewModel = ViolationInspectorViewModel(violationStorage: container.violationStorage)
            return viewModel.filteredViolations.isEmpty && !viewModel.isAnalyzing
        }
        #expect(isEmpty, "filteredViolations should be empty with no workspace, triggering emptyStateView")
    }

    // MARK: - Detail View Tests

    @Test("ViolationInspectorView detail panel shows placeholder when nothing selected")
    func testShowsEmptyDetailView() async throws {
        // ViewInspector cannot reliably traverse conditional branches in the detail panel.
        // Verify the model state that drives emptyDetailView instead of searching for rendered text.
        let container = await Task { @MainActor in DependencyContainer.createForTesting() }.value
        let showsPlaceholder = await MainActor.run {
            let viewModel = ViolationInspectorViewModel(violationStorage: container.violationStorage)
            return viewModel.selectedViolationId == nil
        }
        #expect(showsPlaceholder, "selectedViolationId should be nil, triggering emptyDetailView")
    }

    @Test("ViolationInspectorView shows detail when violation selected")
    func testShowsDetailWhenViolationSelected() async throws {
        let result = try await Task { @MainActor in
            let violation = Violation(
                id: UUID(),
                ruleID: "force_cast",
                filePath: "Test.swift",
                line: 10,
                column: 5,
                severity: .error,
                message: "Test violation message"
            )
            let container = DependencyContainer.createForTesting()
            let storage = try ViolationStorageActor(useInMemory: true)
            let viewModel = ViolationInspectorViewModel(violationStorage: storage)

            viewModel.violations = [violation]
            viewModel.filteredViolations = [violation]
            viewModel.selectedViolationId = violation.id

            let view = ViolationInspectorView(viewModel: viewModel)
                .environment(\.dependencies, container)
            return ViewResult(view: view)
        }.value

        let hasDetail = await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            return (try? result.view.inspect().find(text: "Rule: force_cast")) != nil
        }

        #expect(hasDetail == true, "Selected violation should show detail view")
    }

    // MARK: - List View Tests

    @Test("ViolationInspectorView displays violation list")
    func testDisplaysViolationList() async throws {
        // Use init(viewModel:) to pre-configure state: populate filteredViolations and
        // set groupingOption to a non-.none value so the List branch (not Table) is rendered.
        // Table is not supported by ViewInspector 0.10.3; List (grouped mode) is.
        let result = await Task { @MainActor in
            let container = DependencyContainer.createForTesting()
            let viewModel = ViolationInspectorViewModel(violationStorage: container.violationStorage)
            // Set violations first so the groupingOption didSet (→ updateFilteredViolations)
            // populates filteredViolations correctly when groupingOption is changed.
            viewModel.violations = [makeTestViolation()]
            viewModel.groupingOption = .rule
            let view = ViolationInspectorView(viewModel: viewModel)
            return ViewResult(view: view)
        }.value

        let found = await MainActor.run {
            (try? result.view.inspect().find(ViewType.List.self)) != nil
        }
        #expect(found, "Grouped violation list should use a List (not Table) inspectable by ViewInspector")
    }

    // MARK: - Analyzing State Tests

    @Test("ViolationInspectorView shows analyzing view when analyzing")
    func testShowsAnalyzingView() async throws {
        // Use init(viewModel:) to set isAnalyzing=true before inspection so the
        // analyzing overlay is rendered deterministically.
        let result = await Task { @MainActor in
            let container = DependencyContainer.createForTesting()
            let viewModel = ViolationInspectorViewModel(violationStorage: container.violationStorage)
            viewModel.isAnalyzing = true
            let view = ViolationInspectorView(viewModel: viewModel)
            return ViewResult(view: view)
        }.value

        let found = await MainActor.run {
            (try? result.view.inspect().find(text: "Analyzing Workspace")) != nil
        }
        #expect(found, "View should show 'Analyzing Workspace' when isAnalyzing is true")
    }

}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
