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
    private var externalViewMode: Binding<Int>?

    init(
        ruleRegistry: RuleRegistry,
        externalSearchText: Binding<String>? = nil,
        externalViewMode: Binding<Int>? = nil
    ) {
        _viewModel = State(initialValue: RuleBrowserViewModel(ruleRegistry: ruleRegistry))
        self.externalSearchText = externalSearchText
        self.externalViewMode = externalViewMode
    }

    init(
        viewModel: RuleBrowserViewModel,
        externalSearchText: Binding<String>? = nil,
        externalViewMode: Binding<Int>? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.externalSearchText = externalSearchText
        self.externalViewMode = externalViewMode
    }
    
    var body: some View {
        HSplitView {
            // Left panel: Rule List
            RuleBrowserListView(
                viewModel: viewModel,
                selectedRuleId: $selectedRuleId,
                externalViewMode: externalViewMode
            )
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
        .searchable(text: Bindable(viewModel).searchText, prompt: "Search rules")
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
