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
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: RuleBrowserViewModel
    @State private var selectedRuleId: String?
    private var externalSearchText: Binding<String>?

    init(
        ruleRegistry: RuleRegistry,
        externalSearchText: Binding<String>? = nil
    ) {
        _viewModel = State(initialValue: RuleBrowserViewModel(ruleRegistry: ruleRegistry))
        self.externalSearchText = externalSearchText
    }

    init(
        viewModel: RuleBrowserViewModel,
        externalSearchText: Binding<String>? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.externalSearchText = externalSearchText
    }

    @State private var listWidth: CGFloat = 450

    var body: some View {
        HStack(spacing: 0) {
            // Left panel: Rule List
            RuleBrowserListView(
                viewModel: viewModel,
                selectedRuleId: $selectedRuleId
            )
            .frame(width: listWidth)

            // Draggable divider
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
                                .onChanged { value in
                                    let newWidth = listWidth + value.translation.width
                                    listWidth = min(max(newWidth, 300), 600)
                                }
                        )
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            // Right panel: Rule Detail
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
        .searchable(text: Bindable(viewModel).searchText, prompt: "Search rules")
        .onAppear {
            if let external = externalSearchText {
                viewModel.searchText = external.wrappedValue
            }
            syncEnabledStatesFromConfig()
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
        .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { _ in
            syncEnabledStatesFromConfig()
        }
        .onChange(of: viewModel.filteredRules) { _, newRules in
            // Use newRules directly to avoid re-reading ambient viewModel state
            if let selectedRuleId, !newRules.contains(where: { $0.id == selectedRuleId }) {
                self.selectedRuleId = nil
            }
        }
    }

    private func syncEnabledStatesFromConfig() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else { return }
        let configPath = workspace.configPath
            ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        do {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            ruleRegistry.syncEnabledStates(with: config)
        } catch {
            // No config file or parse error — leave states as-is
        }
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
        .environment(\.ruleRegistry, ruleRegistry)
        .environment(\.dependencies, container)
}
