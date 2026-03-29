//
//  RuleBrowserEmptyState.swift
//  SwiftLintRuleStudio
//
//  Empty state view for the rule browser
//

import SwiftUI
import SwiftLintRuleStudioCore

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
        if !searchText.isEmpty {
            ContentUnavailableView.search
        } else if hasActiveFilters {
            ContentUnavailableView {
                Label("No Rules Found", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try adjusting your filters.")
            } actions: {
                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label("No Rules Found", systemImage: "magnifyingglass")
            } description: {
                Text("Loading rules\u{2026}")
            }
        }
    }
}
