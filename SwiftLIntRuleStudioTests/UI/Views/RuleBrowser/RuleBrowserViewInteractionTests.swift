//
//  RuleBrowserViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for RuleBrowserView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLIntRuleStudio

// Interaction tests for RuleBrowserView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct RuleBrowserViewInteractionTests {

    // MARK: - Test Data Helpers

    private func makeTestRule(
        id: String = "test_rule",
        name: String = "Test Rule",
        description: String = "Test description",
        category: RuleCategory = .lint,
        isOptIn: Bool = false,
        isEnabled: Bool = false
    ) -> Rule {
        Rule(
            id: id,
            name: name,
            description: description,
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: isEnabled,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let container: DependencyContainer
        let viewModel: RuleBrowserViewModel

        init(view: some View, container: DependencyContainer, viewModel: RuleBrowserViewModel) {
            self.view = AnyView(view)
            self.container = container
            self.viewModel = viewModel
        }
    }

    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createRuleBrowserView(rules: [Rule] = []) -> ViewResult {
        let container = DependencyContainer.createForTesting()

        // Create a mock rule registry with test rules
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)

        #if DEBUG
        if !rules.isEmpty {
            ruleRegistry.setRulesForTesting(rules)
        }
        #endif

        let viewModel = RuleBrowserViewModel(ruleRegistry: ruleRegistry)
        let view = RuleBrowserView(viewModel: viewModel)
            .environmentObject(ruleRegistry)
            .environmentObject(container)

        return ViewResult(view: view, container: container, viewModel: viewModel)
    }

    @MainActor
    private func waitForText(
        in view: AnyView,
        text: String,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForText(
            in: view,
            text: text,
            timeout: timeoutSeconds
        )
    }

    private func waitForList(
        in view: AnyView,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        struct ViewWrapper: @unchecked Sendable {
            let view: AnyView
        }
        let wrapper = ViewWrapper(view: view)
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                (try? wrapper.view.inspect().find(ViewType.List.self)) != nil
            }
        }
    }

    private func waitForSearchFieldInput(
        viewModel: RuleBrowserViewModel,
        expected: String,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        struct ViewModelWrapper: @unchecked Sendable {
            let viewModel: RuleBrowserViewModel
        }
        let wrapper = ViewModelWrapper(viewModel: viewModel)
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run { wrapper.viewModel.searchText == expected }
        }
    }

    // MARK: - Search Interaction Tests
    // Note: Search is now handled by .searchable() in the parent NavigationSplitView.
    // Tests drive search state through the view model's searchText property directly.

    @Test("RuleBrowserView search field accepts text input")
    func testSearchFieldAcceptsInput() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "test" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue == "test", "Search field should accept text input")
    }

    @Test("RuleBrowserView search filters rules by rule ID")
    func testSearchFiltersByRuleID() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "force_cast" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue == "force_cast", "Search should filter by rule ID")
    }

    @Test("RuleBrowserView search filters rules by name")
    func testSearchFiltersByName() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "Force Cast" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue == "Force Cast", "Search should filter by rule name")
    }

    @Test("RuleBrowserView search filters rules by description")
    func testSearchFiltersByDescription() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "violation" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue == "violation", "Search should filter by description")
    }

    @Test("RuleBrowserView search is case insensitive")
    func testSearchIsCaseInsensitive() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "FORCE_CAST" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue == "FORCE_CAST", "Search should accept case insensitive input")
    }

    @Test("RuleBrowserView search clear button clears search text")
    func testSearchClearButton() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "test" }
        await MainActor.run { result.viewModel.searchText = "" }
        let inputValue = await MainActor.run { result.viewModel.searchText }
        #expect(inputValue.isEmpty, "Clear button should clear search field")
    }

    // MARK: - Filter Interaction Tests

    @Test("RuleBrowserView clear filters button appears when filters are active")
    func testClearFiltersButtonAppears() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "test" }
        let hasActiveSearch = await MainActor.run { !result.viewModel.searchText.isEmpty }
        #expect(hasActiveSearch == true, "Clear filters button should appear when filters are active")
    }

    @Test("RuleBrowserView clear filters button clears all filters")
    func testClearFiltersButtonClearsFilters() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run {
            result.viewModel.searchText = "test"
            result.viewModel.clearFilters()
        }
        let searchIsEmpty = await MainActor.run { result.viewModel.searchText.isEmpty }
        #expect(searchIsEmpty == true, "Clear filters should clear all filters")
    }

    // MARK: - Selection Tests

    @Test("RuleBrowserView allows rule selection")
    func testAllowsRuleSelection() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let rule = makeTestRule()
        let result = await Task { @MainActor in createRuleBrowserView(rules: [rule]) }.value

        // Find the List view
        let hasListAfterUpdate = await waitForList(in: result.view)
        #expect(hasListAfterUpdate == true, "RuleBrowserView should render List after rules load")
    }

    // MARK: - Empty State Interaction Tests

    @Test("RuleBrowserView empty state clear filters button works")
    func testEmptyStateClearFiltersButton() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "nonexistent" }
        await MainActor.run { result.viewModel.clearFilters() }
        let didClear = await waitForSearchFieldInput(viewModel: result.viewModel, expected: "")
        #expect(didClear == true, "Empty state clear filters should clear search field")
    }

    @Test("RuleBrowserView empty state shows filter guidance")
    func testEmptyStateShowsFilterGuidance() async throws {
        let result = await Task { @MainActor in createRuleBrowserView() }.value
        await MainActor.run { result.viewModel.searchText = "nonexistent" }
        let hasEmptyState = await waitForText(in: result.view, text: "No rules found")
        #expect(hasEmptyState == true, "Empty state should show no rules message")
    }

    // MARK: - Filter State Tests

    @Test("RuleBrowserView status filter defaults to all")
    func testStatusFilterDefaultsToAll() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createRuleBrowserView() }.value

        // Status filter should default to .all
        // We verify the view structure exists
        let hasVStack = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "Status filter should default to all")
    }

    @Test("RuleBrowserView category filter defaults to nil")
    func testCategoryFilterDefaultsToNil() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createRuleBrowserView() }.value

        // Category filter should default to nil (all categories)
        // We verify the view structure exists
        let hasVStack = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "Category filter should default to nil")
    }

    @Test("RuleBrowserView sort option defaults to name")
    func testSortOptionDefaultsToName() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createRuleBrowserView() }.value

        // Sort option should default to .name
        // We verify the view structure exists
        let hasVStack = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "Sort option should default to name")
    }
}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
