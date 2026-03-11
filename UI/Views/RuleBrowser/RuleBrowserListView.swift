//
//  RuleBrowserListView.swift
//  SwiftLintRuleStudio
//
//  Left panel of the rule browser: filter bar, rule list, bulk toolbar
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RuleBrowserListView: View {
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Bindable var viewModel: RuleBrowserViewModel
    @Binding var selectedRuleId: String?
    @State private var bulkSaveError: String?
    @State private var showBulkSaveError = false

    private var hasActiveFilters: Bool {
        !viewModel.searchText.isEmpty
            || viewModel.selectedCategory != nil
            || viewModel.selectedStatus != .all
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and Filters
            RuleBrowserSearchAndFilters(
                searchText: Bindable(viewModel).searchText,
                selectedStatus: Bindable(viewModel).selectedStatus,
                selectedCategory: Bindable(viewModel).selectedCategory,
                selectedSortOption: Bindable(viewModel).selectedSortOption,
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
                    onPreview: {},
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
                List(selection: Bindable(viewModel).selectedRuleIds) {
                    ForEach(viewModel.filteredRules, id: \.id) { rule in
                        RuleListItem(rule: rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.sidebar)
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
                Button(action: viewModel.toggleMultiSelect) {
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
                Button(action: viewModel.clearFilters) {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .disabled(!hasActiveFilters)
                .accessibilityIdentifier("RuleBrowserClearFiltersButton")
            }
        }
        .sheet(item: Bindable(viewModel).bulkDiff) { diff in
            ConfigDiffPreviewView(
                diff: diff,
                ruleName: "\(viewModel.selectedRuleIds.count) rules"
            ) {
                if let engine = currentYAMLEngine {
                    do {
                        try viewModel.saveBulkChanges(yamlEngine: engine)
                        viewModel.isMultiSelectMode = false
                    } catch {
                        bulkSaveError = error.localizedDescription
                        showBulkSaveError = true
                    }
                }
            } onCancel: {
                viewModel.bulkDiff = nil
            }
        }
        .alert("Save Failed", isPresented: $showBulkSaveError) {
            Button("OK") { bulkSaveError = nil }
        } message: {
            Text(bulkSaveError ?? "")
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
