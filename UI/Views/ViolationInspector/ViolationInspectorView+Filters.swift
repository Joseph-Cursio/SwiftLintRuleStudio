import SwiftLintRuleStudioCore
import SwiftUI

extension ViolationInspectorView {
    var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search violations...", text: Bindable(viewModel).searchText)
                    .accessibilityIdentifier("ViolationInspectorSearchField")
            }
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)

            // Filter controls
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    // Rule filter
                    ruleFilterMenu

                    // Severity filter
                    severityFilterMenu

                    // Grouping options
                    groupingMenu

                    // Sort options
                    sortMenu

                    // Clear filters
                    clearFiltersButton
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var clearFiltersButton: some View {
        if !viewModel.searchText.isEmpty ||
            !viewModel.selectedRuleIDs.isEmpty ||
            !viewModel.selectedSeverities.isEmpty {
            Button {
                viewModel.clearFilters()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ViolationSortOption.allCases, id: \.self) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var groupingMenu: some View {
        Menu {
            ForEach(ViolationGroupingOption.allCases, id: \.self) { option in
                Button {
                    viewModel.groupingOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.groupingOption == option {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        } label: {
            Label("Group", systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier("ViolationInspectorGroupingMenu")
    }

    private var severityFilterMenu: some View {
        Menu {
            ForEach([Severity.error, .warning], id: \.self) { severity in
                Button {
                    if viewModel.selectedSeverities.contains(severity) {
                        viewModel.selectedSeverities.remove(severity)
                    } else {
                        viewModel.selectedSeverities.insert(severity)
                    }
                } label: {
                    HStack {
                        Text(severity.rawValue.capitalized)
                        if viewModel.selectedSeverities.contains(severity) {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        } label: {
            Label("Severity", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var ruleFilterMenu: some View {
        if !viewModel.uniqueRules.isEmpty {
            Menu {
                ForEach(viewModel.uniqueRules, id: \.self) { ruleID in
                    Button {
                        if viewModel.selectedRuleIDs.contains(ruleID) {
                            viewModel.selectedRuleIDs.remove(ruleID)
                        } else {
                            viewModel.selectedRuleIDs.insert(ruleID)
                        }
                    } label: {
                        HStack {
                            Text(ruleID)
                            if viewModel.selectedRuleIDs.contains(ruleID) {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            } label: {
                Label("Rule", systemImage: "list.bullet")
            }
        }
    }
}
