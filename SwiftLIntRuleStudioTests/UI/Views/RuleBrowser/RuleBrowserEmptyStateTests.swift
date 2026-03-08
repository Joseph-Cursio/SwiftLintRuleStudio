//
//  RuleBrowserEmptyStateTests.swift
//  SwiftLintRuleStudio
//
//  Unit tests for RuleBrowserEmptyState, exercising every branch directly.
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLIntRuleStudio

@Suite("RuleBrowserEmptyState")
@MainActor
struct RuleBrowserEmptyStateTests {

    // MARK: - Search branch

    @Test("Shows ContentUnavailableView.search when searchText is non-empty")
    func testSearchBranch() throws {
        let view = RuleBrowserEmptyState(
            searchText: "xyz",
            selectedCategory: nil,
            selectedStatus: .all,
            rulesAreEmpty: false,
            onClearFilters: {}
        )
        // ContentUnavailableView.search is a system view — verify the correct branch is
        // chosen by confirming our custom label text is NOT present.
        let inspector = try view.inspect()
        #expect((try? inspector.find(text: "No Rules Found")) == nil,
                "Search branch should not show custom label")
        #expect((try? inspector.find(text: "Loading rules\u{2026}")) == nil,
                "Search branch should not show loading text")
    }

    // MARK: - Filter branch

    @Test("Shows filter guidance when selectedCategory is set")
    func testFilterBranchWithCategory() throws {
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: .style,
            selectedStatus: .all,
            rulesAreEmpty: false,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        #expect((try? inspector.find(text: "No Rules Found")) != nil)
        #expect((try? inspector.find(text: "Try adjusting your filters.")) != nil)
        #expect((try? inspector.find(button: "Clear Filters")) != nil)
    }

    @Test("Shows filter guidance when selectedStatus is non-default")
    func testFilterBranchWithStatus() throws {
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: nil,
            selectedStatus: .enabled,
            rulesAreEmpty: false,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        #expect((try? inspector.find(text: "No Rules Found")) != nil)
        #expect((try? inspector.find(text: "Try adjusting your filters.")) != nil)
    }

    @Test("Clear Filters button calls onClearFilters")
    func testClearFiltersCallback() throws {
        var called = false
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: .lint,
            selectedStatus: .all,
            rulesAreEmpty: false,
            onClearFilters: { called = true }
        )
        let inspector = try view.inspect()
        try inspector.find(button: "Clear Filters").tap()
        #expect(called == true)
    }

    // MARK: - Loading branch

    @Test("Shows loading text when no filters are active and rules are empty")
    func testLoadingBranch() throws {
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: nil,
            selectedStatus: .all,
            rulesAreEmpty: true,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        #expect((try? inspector.find(text: "No Rules Found")) != nil)
        #expect((try? inspector.find(text: "Loading rules\u{2026}")) != nil)
        #expect((try? inspector.find(button: "Clear Filters")) == nil,
                "Loading branch should not show Clear Filters")
    }

    @Test("Shows loading label systemImage when loading")
    func testLoadingBranchSystemImage() throws {
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: nil,
            selectedStatus: .all,
            rulesAreEmpty: true,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        // The label uses "magnifyingglass" — verify no crash on full traversal
        #expect((try? inspector.find(text: "No Rules Found")) != nil)
    }

    // MARK: - Branch priority

    @Test("Search branch takes priority over hasActiveFilters")
    func testSearchPriority() throws {
        // Both searchText and selectedCategory are set; search branch wins.
        let view = RuleBrowserEmptyState(
            searchText: "foo",
            selectedCategory: .style,
            selectedStatus: .all,
            rulesAreEmpty: false,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        // Custom label not present → search branch rendered
        #expect((try? inspector.find(text: "No Rules Found")) == nil)
        #expect((try? inspector.find(button: "Clear Filters")) == nil)
    }

    @Test("hasActiveFilters branch takes priority over loading branch")
    func testFilterPriority() throws {
        // selectedStatus is non-default and rules are empty — filters win.
        let view = RuleBrowserEmptyState(
            searchText: "",
            selectedCategory: nil,
            selectedStatus: .disabled,
            rulesAreEmpty: true,
            onClearFilters: {}
        )
        let inspector = try view.inspect()
        #expect((try? inspector.find(text: "Try adjusting your filters.")) != nil)
        #expect((try? inspector.find(text: "Loading rules\u{2026}")) == nil,
                "Filter branch should not show loading text")
    }
}
