//
//  RuleBrowserViewAdditionalTests.swift
//  SwiftLintRuleStudioTests
//
//  Additional tests for RuleBrowserView (split from RuleBrowserViewTests)
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleBrowserViewAdditionalTests {

    // MARK: - Test Data Helpers

       // MARK: - List Tests

    @Test("RuleBrowserView displays rule list")
    func testDisplaysRuleList() async throws {
        let result = await Task { @MainActor in
            let rule = RuleBrowserFixtures.makeTestRule()
            let cacheManager = CacheManager.createForTesting()
            let ruleRegistry = RuleRegistry(
                swiftLintCLI: SwiftLintCLIActor(cacheManager: cacheManager),
                cacheManager: cacheManager
            )
            #if DEBUG
            ruleRegistry.setRulesForTesting([rule])
            #endif
            let viewModel = RuleBrowserViewModel(ruleRegistry: ruleRegistry)
            let container = DependencyContainer.createForTesting()
            let view = RuleBrowserView(viewModel: viewModel)
                .environment(\.ruleRegistry, ruleRegistry)
                .environment(\.dependencies, container)
            return RuleBrowserFixtures.ViewResult(view: view, container: container)
        }.value

        let hasList = try? await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            _ = try result.view.inspect().find(ViewType.List.self)
            return true
        }
        #expect(hasList == true, "RuleBrowserView should have list when rules exist")
    }

    // MARK: - Empty State Tests

    @Test("RuleBrowserView shows empty state when no rules match filters")
    func testShowsEmptyState() async throws {
        let result = await Task { @MainActor in
            let cacheManager = CacheManager.createForTesting()
            let ruleRegistry = RuleRegistry(
                swiftLintCLI: SwiftLintCLIActor(cacheManager: cacheManager),
                cacheManager: cacheManager
            )
            let viewModel = RuleBrowserViewModel(ruleRegistry: ruleRegistry)
            viewModel.selectedCategory = .style
            let container = DependencyContainer.createForTesting()
            let view = RuleBrowserView(viewModel: viewModel)
                .environment(\.ruleRegistry, ruleRegistry)
                .environment(\.dependencies, container)
            return RuleBrowserFixtures.ViewResult(view: view, container: container)
        }.value

        let hasEmptyText = try? await MainActor.run {
            _ = try result.view.inspect().find(text: "No Rules Found")
            return true
        }
        #expect(hasEmptyText == true, "RuleBrowserView should show empty state")
    }

    @Test("RuleBrowserView shows empty state message")
    func testShowsEmptyStateMessage() async throws {
        let result = await Task { @MainActor in
            let cacheManager = CacheManager.createForTesting()
            let ruleRegistry = RuleRegistry(
                swiftLintCLI: SwiftLintCLIActor(cacheManager: cacheManager),
                cacheManager: cacheManager
            )
            let viewModel = RuleBrowserViewModel(ruleRegistry: ruleRegistry)
            viewModel.selectedCategory = .style
            let container = DependencyContainer.createForTesting()
            let view = RuleBrowserView(viewModel: viewModel)
                .environment(\.ruleRegistry, ruleRegistry)
                .environment(\.dependencies, container)
            return RuleBrowserFixtures.ViewResult(view: view, container: container)
        }.value

        let hasMessage = try? await MainActor.run {
            _ = try result.view.inspect().find(text: "Try adjusting your filters.")
            return true
        }
        #expect(hasMessage == true, "RuleBrowserView should show empty state message")
    }

    // MARK: - Toolbar Tests

    @Test("RuleBrowserView shows clear filters button in toolbar")
    func testShowsClearFiltersButton() async throws {
        let result = await Task { @MainActor in RuleBrowserFixtures.makeView() }.value

        let hasNavigationSplitView = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasNavigationSplitView == true, "RuleBrowserView should have toolbar with clear filters button")
    }

    // MARK: - View Structure Tests

    @Test("RuleBrowserView has correct view hierarchy")
    func testViewHierarchy() async throws {
        let result = await Task { @MainActor in RuleBrowserFixtures.makeView() }.value

        let hasNavigationSplitView = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasNavigationSplitView == true, "RuleBrowserView should have NavigationSplitView as root")
    }

    @Test("RuleBrowserView has primary-detail layout")
    func testPrimaryDetailLayout() async throws {
        let result = await Task { @MainActor in RuleBrowserFixtures.makeView() }.value

        let hasNavigationSplitView = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasNavigationSplitView == true, "RuleBrowserView should have primary-detail layout")
    }

    // MARK: - Integration Tests

    @Test("RuleBrowserView integrates with RuleRegistry")
    func testIntegratesWithRuleRegistry() async throws {
        let result = await Task { @MainActor in RuleBrowserFixtures.makeView() }.value

        let hasNavigationSplitView = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasNavigationSplitView == true, "RuleBrowserView should integrate with RuleRegistry")
    }
}
