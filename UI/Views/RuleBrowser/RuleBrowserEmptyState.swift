//
//  RuleBrowserEmptyState.swift
//  SwiftLintRuleStudio
//
//  Empty state view for the rule browser
//

import SwiftUI

struct RuleBrowserEmptyState: View {
    let searchText: String
    let selectedCategory: RuleCategory?
    let selectedStatus: RuleStatusFilter
    let rulesAreEmpty: Bool
    let onClearFilters: () -> Void

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedCategory != nil || selectedStatus != .all
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No rules found")
                .font(.headline)
                .foregroundStyle(.secondary)

            if hasActiveFilters {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
            } else if rulesAreEmpty {
                Text("Loading rules...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
