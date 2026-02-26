//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RuleBrowserView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @EnvironmentObject var dependencies: DependencyContainer
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: RuleBrowserViewModel
    @State private var selectedRuleId: String?
    private var externalSearchText: Binding<String>?
    private var externalViewMode: Binding<Int>?

    init(
        ruleRegistry: RuleRegistry,
        externalSearchText: Binding<String>? = nil,
        externalViewMode: Binding<Int>? = nil
    ) {
        _viewModel = StateObject(wrappedValue: RuleBrowserViewModel(ruleRegistry: ruleRegistry))
        self.externalSearchText = externalSearchText
        self.externalViewMode = externalViewMode
    }

    init(
        viewModel: RuleBrowserViewModel,
        externalSearchText: Binding<String>? = nil,
        externalViewMode: Binding<Int>? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.externalSearchText = externalSearchText
        self.externalViewMode = externalViewMode
    }
    
    var body: some View {
        HSplitView {
            // Left panel: Rule List
            ruleListView
                .frame(minWidth: 450, idealWidth: 450, maxWidth: 560)

            // Right panel: Rule Detail
            Group {
                if let selectedRuleId = selectedRuleId,
                   let selectedRule = ruleRegistry.rules.first(where: { $0.id == selectedRuleId }) {
                    RuleDetailView(rule: selectedRule)
                        .id(selectedRuleId) // Force view recreation when selection changes
                } else {
                    // Empty view - no message shown
                    Color.clear
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search rules")
        .onAppear {
            if let external = externalSearchText {
                viewModel.searchText = external.wrappedValue
            }
        }
        .onChange(of: externalSearchText?.wrappedValue ?? "") { _, newValue in
            if let external = externalSearchText, external.wrappedValue != viewModel.searchText {
                viewModel.searchText = newValue
            }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            if let external = externalSearchText, external.wrappedValue != newValue {
                external.wrappedValue = newValue
            }
        }
        .navigationTitle("Rules")
        .onChange(of: viewModel.filteredRules) { _, newRules in
            // Use newRules directly to avoid re-reading ambient viewModel state
            if let selectedRuleId, !newRules.contains(where: { $0.id == selectedRuleId }) {
                self.selectedRuleId = nil
            }
        }
    }
    
    private var ruleListView: some View {
        let hasActiveFilters = !viewModel.searchText.isEmpty
            || viewModel.selectedCategory != nil
            || viewModel.selectedStatus != .all
        return VStack(spacing: 0) {
            // Search and Filters
            RuleBrowserSearchAndFilters(
                searchText: $viewModel.searchText,
                selectedStatus: $viewModel.selectedStatus,
                selectedCategory: $viewModel.selectedCategory,
                selectedSortOption: $viewModel.selectedSortOption,
                categoryCounts: viewModel.categoryCounts
            )

            Divider()

            // Bulk Operation Toolbar (shown in multi-select mode)
            if viewModel.isMultiSelectMode {
                BulkOperationToolbar(
                    selectedCount: viewModel.selectedRuleIds.count,
                    onEnableAll: {
                        if let engine = currentYAMLEngine {
                            viewModel.enableSelectedRules(yamlEngine: engine)
                        }
                    },
                    onDisableAll: {
                        if let engine = currentYAMLEngine {
                            viewModel.disableSelectedRules(yamlEngine: engine)
                        }
                    },
                    onSetSeverity: { severity in
                        if let engine = currentYAMLEngine {
                            viewModel.setSeverityForSelected(severity, yamlEngine: engine)
                        }
                    },
                    onPreview: {
                        viewModel.showBulkDiffPreview = true
                    },
                    onClearSelection: {
                        viewModel.clearSelection()
                    }
                )
            }

            // Rules List
            if viewModel.filteredRules.isEmpty {
                RuleBrowserEmptyState(
                    searchText: viewModel.searchText,
                    selectedCategory: viewModel.selectedCategory,
                    selectedStatus: viewModel.selectedStatus,
                    rulesAreEmpty: ruleRegistry.rules.isEmpty,
                    onClearFilters: { viewModel.clearFilters() }
                )
            } else if viewModel.isMultiSelectMode {
                // Multi-select remains list-based for clarity and keyboard selection
                List(selection: $viewModel.selectedRuleIds) {
                    ForEach(viewModel.filteredRules, id: \.id) { rule in
                        RuleListItem(rule: rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.sidebar)
            } else if (externalViewMode?.wrappedValue ?? 0) == 1 {
                // Grid mode
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 16, alignment: .top)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(viewModel.filteredRules, id: \.id) { rule in
                            Button {
                                selectedRuleId = rule.id
                            } label: {
                                RuleListItem(rule: rule)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { ruleContextMenu(for: rule) }
                        }
                    }
                    .padding(16)
                }
            } else {
                // List mode
                List(selection: $selectedRuleId) {
                    ForEach(viewModel.filteredRules, id: \.id) { rule in
                        RuleListItem(rule: rule)
                            .tag(rule.id)
                            .contextMenu { ruleContextMenu(for: rule) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.toggleMultiSelect()
                } label: {
                    Label(
                        viewModel.isMultiSelectMode ? "Exit Multi-Select" : "Multi-Select",
                        systemImage: viewModel.isMultiSelectMode
                            ? "checklist.checked" : "checklist"
                    )
                }
                .accessibilityIdentifier("RuleBrowserMultiSelectButton")
            }
            ToolbarItem(placement: .primaryAction) {
                RulePresetPicker { preset in
                    viewModel.applyPreset(preset)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .disabled(!hasActiveFilters)
                .accessibilityIdentifier("RuleBrowserClearFiltersButton")
            }
        }
        .sheet(isPresented: $viewModel.showBulkDiffPreview) {
            if let diff = viewModel.bulkDiff {
                ConfigDiffPreviewView(
                    diff: diff,
                    ruleName: "\(viewModel.selectedRuleIds.count) rules"
                ) {
                    if let engine = currentYAMLEngine {
                        do {
                            try viewModel.saveBulkChanges(yamlEngine: engine)
                            viewModel.showBulkDiffPreview = false
                            viewModel.isMultiSelectMode = false
                        } catch {
                            print("Error saving bulk changes: \(error)")
                        }
                    }
                } onCancel: {
                    viewModel.showBulkDiffPreview = false
                }
            }
        }
    }

    @ViewBuilder
    private func ruleContextMenu(for rule: Rule) -> some View {
        Button(rule.isEnabled ? "Disable Rule" : "Enable Rule") {
            if let engine = currentYAMLEngine {
                viewModel.toggleRule(rule, yamlEngine: engine)
            }
        }
        Button("Copy Rule Identifier") {
#if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rule.id, forType: .string)
#endif
        }
        Divider()
        Button("Simulate Impact") {
            NotificationCenter.default.post(
                name: .simulateImpactRequested,
                object: nil,
                userInfo: ["ruleId": rule.id]
            )
        }
    }

    private var currentYAMLEngine: YAMLConfigurationEngine? {
        guard let workspace = dependencies.workspaceManager.currentWorkspace,
              let configPath = workspace.configPath else { return nil }
        return YAMLConfigurationEngine(configPath: configPath)
    }
    
}

// MARK: - Extracted subviews (kept file-private to avoid counting toward RuleBrowserView body length)

private struct RuleBrowserSearchAndFilters: View {
    @Binding var searchText: String
    @Binding var selectedStatus: RuleStatusFilter
    @Binding var selectedCategory: RuleCategory?
    @Binding var selectedSortOption: SortOption
    let categoryCounts: [RuleCategory: Int]

    var body: some View {
        VStack(spacing: 12) {
            // Filters (search is handled by .searchable() in the parent NavigationSplitView)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Status Filter
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(RuleStatusFilter.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
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
                    .frame(width: 150)

                    // Sort Option
                    Picker("Sort", selection: $selectedSortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)

                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct RuleBrowserEmptyState: View {
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

#if DEBUG
extension RuleBrowserView {
    /// A minimal view instance used solely to call string-processing helper methods in tests.
    /// These methods do not use the registry or viewModel, so any registry suffices.
    @MainActor private static func makeTestingInstance() -> RuleBrowserView {
        let cacheManager = CacheManager()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let registry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        return RuleBrowserView(ruleRegistry: registry)
    }

    @MainActor static func convertMarkdownToPlainTextForTesting(_ content: String) -> String {
        makeTestingInstance().convertMarkdownToPlainText(content: content)
    }

    @MainActor static func stripHTMLTagsForTesting(_ content: String) -> String {
        makeTestingInstance().stripHTMLTags(from: content)
    }

    @MainActor static func processContentForDisplayForTesting(_ content: String) -> String {
        makeTestingInstance().processContentForDisplay(content: content)
    }

    @MainActor static func convertMarkdownToHTMLForTesting(_ content: String) -> String {
        makeTestingInstance().convertMarkdownToHTML(content: content)
    }

    @MainActor static func wrapHTMLInDocumentForTesting(body: String, colorScheme: ColorScheme) -> String {
        makeTestingInstance().wrapHTMLInDocument(body: body, colorScheme: colorScheme)
    }
}
#endif

#Preview {
    let cacheManager = CacheManager()
    let swiftLintCLI = SwiftLintCLI(cacheManager: CacheManager())
    let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
    let container = DependencyContainer(
        ruleRegistry: ruleRegistry,
        swiftLintCLI: swiftLintCLI,
        cacheManager: cacheManager
    )
    
    RuleBrowserView(ruleRegistry: ruleRegistry)
        .environmentObject(ruleRegistry)
        .environmentObject(container)
}
