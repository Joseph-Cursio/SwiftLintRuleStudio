//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The right-hand pane: the selected rule, or nothing.
///
/// Takes the resolved rule. The browser around it re-renders on every pixel of a divider drag —
/// `listWidth` is `@State` and the gesture writes it continuously — and on every keystroke in the
/// search field, neither of which changes which rule is selected.
private struct RuleBrowserDetailPanel: View {
    let rule: Rule?

    var body: some View {
        Group {
            if let rule {
                RuleDetailView(rule: rule)
                    .id(rule.id)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

            RuleBrowserDetailPanel(
                rule: selectedRuleId.flatMap { identifier in
                    ruleRegistry.rules.first { $0.id == identifier }
                }
            )
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
            dropSelectionIfFiltered(from: newRules)
        }
    }

    private func dropSelectionIfFiltered(from newRules: [Rule]) {
        selectedRuleId = Self.selection(selectedRuleId, survivingIn: newRules)
    }

    /// The selected rule, or `nil` when the new filter no longer contains it.
    ///
    /// A total function of the two things it depends on, lifted out of an `onChange` closure no
    /// test could fire. Three cases and only one of them was obvious from the closure: nothing
    /// selected stays nothing, a selection the filter still contains survives, and a selection
    /// the filter has dropped is cleared — which is the case that keeps the detail pane from
    /// showing a rule the list no longer offers.
    static func selection(_ current: String?, survivingIn rules: [Rule]) -> String? {
        guard let current, rules.contains(where: { $0.id == current }) else { return nil }
        return current
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
        guard let config = try? YAMLConfigurationEngine.loadConfig(at: configPath) else { return }
        ruleRegistry.syncEnabledStates(with: config)
    }
}

#Preview {
    let cacheManager = CacheManager()
    let swiftLintCLI = UnconfiguredSwiftLintBackend()
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
