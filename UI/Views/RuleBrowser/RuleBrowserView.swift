//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct RuleBrowserView: View {
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: RuleBrowserViewModel
    @Binding var selectedRuleId: String?
    private var externalSearchText: Binding<String>?

    init(
        ruleRegistry: RuleRegistry,
        externalSearchText: Binding<String>? = nil,
        selectedRuleId: Binding<String?> = .constant(nil)
    ) {
        _viewModel = State(initialValue: RuleBrowserViewModel(ruleRegistry: ruleRegistry))
        self.externalSearchText = externalSearchText
        _selectedRuleId = selectedRuleId
    }

    init(
        viewModel: RuleBrowserViewModel,
        externalSearchText: Binding<String>? = nil,
        selectedRuleId: Binding<String?> = .constant(nil)
    ) {
        _viewModel = State(initialValue: viewModel)
        self.externalSearchText = externalSearchText
        _selectedRuleId = selectedRuleId
    }

    @State private var listWidth: Double = 450

    var body: some View {
        HStack(spacing: 0) {
            RuleBrowserListView(
                viewModel: viewModel,
                selectedRuleId: $selectedRuleId
            )
            .frame(width: listWidth)

            draggableDivider

            detailPanel
        }
        .searchable(text: Bindable(viewModel).searchText, prompt: "Search rules")
        .onAppear(perform: handleAppear)
        .onChange(of: externalSearchText?.wrappedValue ?? "", handleExternalSearchChange)
        .onChange(of: viewModel.searchText, handleInternalSearchChange)
        .navigationTitle("Rules")
        .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { _ in
            syncEnabledStatesFromConfig()
        }
        .onChange(of: viewModel.filteredRules) { _, newRules in
            if let selectedRuleId, !newRules.contains(where: { $0.id == selectedRuleId }) {
                self.selectedRuleId = nil
            }
        }
    }

    private var draggableDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged(handleDividerDrag)
                    )
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var detailPanel: some View {
        Group {
            if let selectedRuleId = selectedRuleId,
               let selectedRule = ruleRegistry.rules.first(where: { $0.id == selectedRuleId }) {
                RuleDetailView(rule: selectedRule)
                    .id(selectedRuleId)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleAppear() {
        if let external = externalSearchText {
            viewModel.searchText = external.wrappedValue
        }
        syncEnabledStatesFromConfig()
    }

    private func handleExternalSearchChange(_: String, _ newValue: String) {
        if let external = externalSearchText, external.wrappedValue != viewModel.searchText {
            viewModel.searchText = newValue
        }
    }

    private func handleInternalSearchChange(_: String, _ newValue: String) {
        if let external = externalSearchText, external.wrappedValue != newValue {
            external.wrappedValue = newValue
        }
    }

    private func handleDividerDrag(_ value: DragGesture.Value) {
        let newWidth = listWidth + value.translation.width
        listWidth = min(max(newWidth, 300), 600)
    }

    private func syncEnabledStatesFromConfig() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else { return }
        let configPath = workspace.configPath
            ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        guard (try? yamlEngine.load()) != nil else { return }
        let config = yamlEngine.getConfig()
        ruleRegistry.syncEnabledStates(with: config)
    }
}

#Preview {
    let cacheManager = CacheManager()
    let swiftLintCLI = SwiftLintCLIActor(cacheManager: CacheManager())
    let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
    let container = DependencyContainer(
        ruleRegistry: ruleRegistry,
        swiftLintCLI: swiftLintCLI,
        cacheManager: cacheManager
    )

    RuleBrowserView(ruleRegistry: ruleRegistry)
        .environment(\.ruleRegistry, ruleRegistry)
        .environment(\.dependencies, container)
}
