//
//  RuleBrowserSearchAndFilters.swift
//  SwiftLintRuleStudio
//
//  Filter bar for the rule browser
//

import SwiftLintRuleStudioCore
import SwiftUI

struct RuleBrowserSearchAndFilters: View {
    @Binding var searchText: String
    @Binding var selectedStatus: RuleStatusFilter
    @Binding var selectedType: RuleTypeFilter
    @Binding var selectedCategory: RuleCategory?
    @Binding var selectedSortOption: SortOption
    let categoryCounts: [RuleCategory: Int]

    var body: some View {
        // Filters (search is handled by .searchable() in the parent NavigationSplitView).
        // Four menus don't fit a narrow list column, so when they can't share a row,
        // split them: which rules (status, type) above how they're grouped and ordered.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statusPicker()
                typePicker()
                categoryPicker()
                sortPicker()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusPicker()
                    typePicker()
                }
                HStack(spacing: 8) {
                    categoryPicker()
                    sortPicker()
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func statusPicker() -> some View {
        Picker("Status", selection: $selectedStatus) {
            ForEach(RuleStatusFilter.allCases) { status in
                Text(status.displayName).tag(status)
            }
        }
        .pickerStyle(.menu)
        .help("Show rules that are on or off in this configuration")
        .accessibilityIdentifier("RuleBrowserStatusFilter")
    }

    private func typePicker() -> some View {
        Picker("Type", selection: $selectedType) {
            ForEach(RuleTypeFilter.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.menu)
        .help("Show rules SwiftLint runs by default, or opt-in rules it runs only when enabled")
        .accessibilityIdentifier("RuleBrowserTypeFilter")
    }

    private func categoryPicker() -> some View {
        Picker("Category", selection: $selectedCategory) {
            Text("All Categories").tag(nil as RuleCategory?)
            ForEach(RuleCategory.allCases) { category in
                HStack {
                    Text(category.displayName)
                    if let count = categoryCounts[category] {
                        Text("(\(count))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .tag(category as RuleCategory?)
            }
        }
        .pickerStyle(.menu)
    }

    private func sortPicker() -> some View {
        Picker("Sort", selection: $selectedSortOption) {
            ForEach(SortOption.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}
