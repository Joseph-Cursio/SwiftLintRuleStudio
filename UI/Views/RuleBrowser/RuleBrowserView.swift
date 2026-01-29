//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleBrowserView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: RuleBrowserViewModel
    @State private var selectedRuleId: String?
    
    init() {
        // Create a temporary ruleRegistry for initialization
        // Will be updated in onAppear with the actual one from environment
        let tempRegistry = RuleRegistry(
            swiftLintCLI: SwiftLintCLI(cacheManager: CacheManager()),
            cacheManager: CacheManager()
        )
        _viewModel = StateObject(wrappedValue: RuleBrowserViewModel(ruleRegistry: tempRegistry))
    }

    init(ruleRegistry: RuleRegistry) {
        _viewModel = StateObject(wrappedValue: RuleBrowserViewModel(ruleRegistry: ruleRegistry))
    }

    init(viewModel: RuleBrowserViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        NavigationSplitView {
            // First panel: Rule List
            ruleListView
                .navigationSplitViewColumnWidth(min: 200, ideal: 300)
        } detail: {
            Group {
                // Second panel: Rule Detail (only shown when rule is selected)
            if let selectedRuleId = selectedRuleId,
               let selectedRule = ruleRegistry.rules.first(where: { $0.id == selectedRuleId }) {
                RuleDetailView(rule: selectedRule)
                        .id(selectedRuleId) // Force view recreation when selection changes
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        // NavigationSplitView detail column adds default padding (~20-24 points on macOS)
                        // We use negative padding to align content with the toolbar's left edge
                        .padding(.leading, -300) // Fixed value to align with toolbar
            } else {
                    // Empty view - no message shown
                    Color.clear
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 500)
        }
        .navigationTitle("Rules")
        .onAppear {
            // Update viewModel with the actual ruleRegistry from environment
            viewModel.ruleRegistry = ruleRegistry
        }
        .onChange(of: viewModel.filteredRules) {
            // Clear selection if the selected rule is no longer in the filtered list
            if let selectedRuleId = selectedRuleId,
               !viewModel.filteredRules.contains(where: { $0.id == selectedRuleId }) {
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
            searchAndFiltersView
            
            Divider()
            
            // Rules List
            if viewModel.filteredRules.isEmpty {
                emptyStateView
            } else {
                List(selection: $selectedRuleId) {
                    ForEach(viewModel.filteredRules, id: \.id) { rule in
                        RuleListItem(rule: rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .disabled(!hasActiveFilters)
            }
        }
    }
    
    private var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                TextField("Search rules...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Clear search text")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Status Filter
                    Picker("Status", selection: $viewModel.selectedStatus) {
                        ForEach(RuleStatusFilter.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    // Category Filter
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        Text("All Categories").tag(nil as RuleCategory?)
                        ForEach(RuleCategory.allCases) { category in
                            HStack {
                                Text(category.displayName)
                                if let count = viewModel.categoryCounts[category] {
                                    Text("(\(count))")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .tag(category as RuleCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    
                    // Sort Option
                    Picker("Sort", selection: $viewModel.selectedSortOption) {
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
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            Text("No rules found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if !viewModel.searchText.isEmpty || viewModel.selectedCategory != nil || viewModel.selectedStatus != .all {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.bordered)
            } else if ruleRegistry.rules.isEmpty {
                Text("Loading rules...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
}

#if DEBUG
extension RuleBrowserView {
    @MainActor static func convertMarkdownToPlainTextForTesting(_ content: String) -> String {
        RuleBrowserView().convertMarkdownToPlainText(content: content)
    }

    @MainActor static func stripHTMLTagsForTesting(_ content: String) -> String {
        RuleBrowserView().stripHTMLTags(from: content)
    }

    @MainActor static func processContentForDisplayForTesting(_ content: String) -> String {
        RuleBrowserView().processContentForDisplay(content: content)
    }

    @MainActor static func convertMarkdownToHTMLForTesting(_ content: String) -> String {
        RuleBrowserView().convertMarkdownToHTML(content: content)
    }

    @MainActor static func wrapHTMLInDocumentForTesting(body: String, colorScheme: ColorScheme) -> String {
        RuleBrowserView().wrapHTMLInDocument(body: body, colorScheme: colorScheme)
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
    
    RuleBrowserView()
        .environmentObject(ruleRegistry)
        .environmentObject(container)
}
