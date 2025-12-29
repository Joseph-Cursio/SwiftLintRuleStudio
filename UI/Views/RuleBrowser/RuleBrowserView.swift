//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleBrowserView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @StateObject private var viewModel: RuleBrowserViewModel
    @State private var selectedRuleId: String?
    @State private var expandedCategories: Set<RuleCategory> = Set(RuleCategory.allCases)
    
    init() {
        // Create a temporary ruleRegistry for initialization
        // Will be updated in onAppear with the actual one from environment
        let tempRegistry = RuleRegistry(
            swiftLintCLI: SwiftLintCLI(cacheManager: CacheManager()),
            cacheManager: CacheManager()
        )
        _viewModel = StateObject(wrappedValue: RuleBrowserViewModel(ruleRegistry: tempRegistry))
    }
    
    var body: some View {
        NavigationSplitView {
            // Master: Rule List
            ruleListView
        } detail: {
            // Detail: Rule Detail or Empty State
            if let selectedRuleId = selectedRuleId,
               let selectedRule = ruleRegistry.rules.first(where: { $0.id == selectedRuleId }) {
                RuleDetailView(rule: selectedRule)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Rules")
        .onAppear {
            // Update viewModel with the actual ruleRegistry from environment
            viewModel.ruleRegistry = ruleRegistry
        }
        .onChange(of: viewModel.groupedRules) {
            // Clear selection if the selected rule is no longer in the filtered list
            if let selectedRuleId = selectedRuleId,
               !viewModel.groupedRules.flatMap({ $0.rules }).contains(where: { $0.id == selectedRuleId }) {
                self.selectedRuleId = nil
            }
        }
    }
    
    private var ruleListView: some View {
        VStack(spacing: 0) {
            // Search and Filters
            searchAndFiltersView
            
            Divider()
            
            // Rules List
            if viewModel.groupedRules.isEmpty {
                emptyStateView
            } else {
                List(selection: $selectedRuleId) {
                    ForEach(viewModel.groupedRules, id: \.category) { category, rules in
                        let isExpanded = Binding<Bool>(
                            get: { expandedCategories.contains(category) },
                            set: { isExpanding in
                                if isExpanding {
                                    expandedCategories.insert(category)
                                } else {
                                    expandedCategories.remove(category)
                                }
                            }
                        )

                        DisclosureGroup(isExpanded: isExpanded) {
                            ForEach(rules, id: \.id) { rule in
                                RuleListItem(rule: rule)
                                    .tag(rule.id)
                            }
                        } label: {
                            HStack {
                                Text(category.displayName)
                                    .font(.headline)
                                Spacer()
                                Text("(\(rules.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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
                .disabled(viewModel.searchText.isEmpty && viewModel.selectedCategory == nil && viewModel.selectedStatus == .all)
            }
        }
    }
    
    private var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search rules...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
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
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select a rule to view details")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let cacheManager = CacheManager()
    let swiftLintCLI = SwiftLintCLI(cacheManager: CacheManager())
    let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
    let container = DependencyContainer(
        ruleRegistry: ruleRegistry,
        swiftLintCLI: swiftLintCLI,
        cacheManager: cacheManager
    )
    
    return RuleBrowserView()
        .environmentObject(ruleRegistry)
        .environmentObject(container)
}
