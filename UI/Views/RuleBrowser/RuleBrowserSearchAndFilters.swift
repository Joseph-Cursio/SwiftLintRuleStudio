//
//  RuleBrowserSearchAndFilters.swift
//  SwiftLintRuleStudio
//
//  Filter bar for the rule browser
//

import SwiftUI
import SwiftLintRuleStudioCore

struct RuleBrowserSearchAndFilters: View {
    @Binding var searchText: String
    @Binding var selectedStatus: RuleStatusFilter
    @Binding var selectedCategory: RuleCategory?
    @Binding var selectedSortOption: SortOption
    let categoryCounts: [RuleCategory: Int]

    var body: some View {
        VStack(spacing: 8) {
            // Filters (search is handled by .searchable() in the parent NavigationSplitView)
            HStack(spacing: 8) {
                // Status Filter
                Picker("Status", selection: $selectedStatus) {
                    ForEach(RuleStatusFilter.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("RuleBrowserStatusFilter")

                // Category Filter
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

                // Sort Option
                Picker("Sort", selection: $selectedSortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
}
