import SwiftUI

extension ViolationInspectorView {
    var violationListView: some View {
        VStack(spacing: 0) {
            // Search and Filters
            searchAndFiltersView

            Divider()

            // Statistics
            statisticsView

            Divider()

            // Violations List
            if viewModel.isAnalyzing {
                analyzingView
            } else if viewModel.filteredViolations.isEmpty {
                emptyStateView
            } else {
                if viewModel.groupingOption == .none {
                    Table(
                        viewModel.filteredViolations,
                        selection: $viewModel.selectedViolationIds,
                        sortOrder: $viewModel.tableSortOrder
                    ) {
                        TableColumn("Severity", value: \.severity.rawValue) { violation in
                            Text(violation.severity.rawValue.capitalized)
                                .foregroundStyle(violation.severity == .error ? .red : .orange)
                        }
                        .width(min: 60, ideal: 70, max: 80)

                        TableColumn("File", value: \.filePath) { violation in
                            Text(URL(fileURLWithPath: violation.filePath).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        TableColumn("Line", value: \.line) { violation in
                            Text("\(violation.line)")
                                .monospacedDigit()
                        }
                        .width(min: 40, ideal: 50, max: 60)

                        TableColumn("Rule ID", value: \.ruleID)
                            .width(min: 80, ideal: 120, max: 180)
                    }
                    .onChange(of: viewModel.tableSortOrder) { _, _ in
                        viewModel.sortFilteredViolations()
                    }
                } else {
                    groupedViolationListView
                }
            }
        }
    }

    var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search violations...", text: $viewModel.searchText)
                    .accessibilityIdentifier("ViolationInspectorSearchField")
            }
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)

            // Filter controls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Rule filter
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

                    // Severity filter
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

                    // Grouping options
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

                    // Sort options
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

                    // Clear filters
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
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    var statisticsView: some View {
        HStack(spacing: 20) {
            StatisticBadge(
                label: "Total",
                value: "\(viewModel.violationCount)",
                color: .primary
            )

            StatisticBadge(
                label: "Errors",
                value: "\(viewModel.errorCount)",
                color: .red
            )

            StatisticBadge(
                label: "Warnings",
                value: "\(viewModel.warningCount)",
                color: .orange
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)

            Text("Analyzing Workspace")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Running SwiftLint to detect violations...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("This may take a few minutes for large projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Violations")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No violations match your current filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !viewModel.searchText.isEmpty ||
                !viewModel.selectedRuleIDs.isEmpty ||
                !viewModel.selectedSeverities.isEmpty {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Select a Violation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select a violation from the list to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var groupedViolationListView: some View {
        List(selection: $viewModel.selectedViolationIds) {
            let grouped = groupViolations(viewModel.filteredViolations, by: viewModel.groupingOption)

            ForEach(orderedGroupKeys(for: grouped, option: viewModel.groupingOption), id: \.self) { groupKey in
                SwiftUI.Section {
                    ForEach(grouped[groupKey] ?? [], id: \.id) { violation in
                        ViolationListItem(violation: violation)
                            .tag(violation.id)
                    }
                } header: {
                    Text(groupKey).font(.headline)
                }
            }
        }
        .listStyle(.sidebar)
    }

    func orderedGroupKeys(
        for grouped: [String: [Violation]],
        option: ViolationGroupingOption
    ) -> [String] {
        switch option {
        case .none:
            return grouped.keys.sorted()
        case .severity:
            let preferredOrder = ["Error", "Warning"]
            let ordered = preferredOrder.filter { grouped[$0] != nil }
            let remaining = grouped.keys.filter { !preferredOrder.contains($0) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return ordered + remaining
        case .file, .rule:
            return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    func groupViolations(_ violations: [Violation], by option: ViolationGroupingOption) -> [String: [Violation]] {
        switch option {
        case .none:
            return ["All": violations]
        case .file:
            return Dictionary(grouping: violations, by: { $0.filePath })
        case .rule:
            return Dictionary(grouping: violations, by: { $0.ruleID })
        case .severity:
            return Dictionary(grouping: violations, by: { $0.severity.rawValue.capitalized })
        }
    }
}
