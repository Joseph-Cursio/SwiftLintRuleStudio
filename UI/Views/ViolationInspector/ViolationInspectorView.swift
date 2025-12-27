//
//  ViolationInspectorView.swift
//  SwiftLintRuleStudio
//
//  Main view for inspecting violations
//

import SwiftUI

struct ViolationInspectorView: View {
    @EnvironmentObject var dependencies: DependencyContainer
    @StateObject private var viewModel: ViolationInspectorViewModel
    @State private var selectedViolationId: UUID?
    @State private var workspaceId: UUID?
    
    init() {
        // Create temporary storage for initialization
        // Will be updated in onAppear with actual storage from dependencies
        // Use do-catch to handle initialization errors gracefully
        let tempStorage: ViolationStorage
        do {
            tempStorage = try ViolationStorage(useInMemory: true)
        } catch {
            // If initialization fails, log the error and create a fallback
            // This prevents crashes and allows the view to still render
            print("⚠️ Failed to initialize ViolationStorage: \(error)")
            // Try to create a file-based storage as fallback
            if let fallbackStorage = try? ViolationStorage(useInMemory: false) {
                tempStorage = fallbackStorage
            } else {
                // Last resort: create in-memory storage again (should work after fix)
                // This will crash if there's a fundamental issue, but that's better than silent failure
                fatalError("Failed to initialize ViolationStorage: \(error). This indicates a critical database configuration issue.")
            }
        }
        _viewModel = StateObject(wrappedValue: ViolationInspectorViewModel(violationStorage: tempStorage))
    }
    
    var body: some View {
        NavigationSplitView {
            // Master: Violation List
            violationListView
        } detail: {
            // Detail: Violation Detail or Empty State
            if let selectedViolationId = selectedViolationId,
               let violation = viewModel.filteredViolations.first(where: { $0.id == selectedViolationId }) {
                ViolationDetailView(
                    violation: violation,
                    onSuppress: { reason in
                        Task {
                            try? await viewModel.suppressSelectedViolations(reason: reason)
                        }
                    },
                    onResolve: {
                        Task {
                            try? await viewModel.resolveSelectedViolations()
                        }
                    }
                )
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Violations")
        .onAppear {
            // Update viewModel with actual storage and analyzer from dependencies
            viewModel.violationStorage = dependencies.violationStorage
            viewModel.workspaceAnalyzer = dependencies.workspaceAnalyzer
            
            // Load violations for current workspace if available
            if let workspace = dependencies.workspaceManager.currentWorkspace {
                Task {
                    do {
                        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
                    } catch {
                        print("Error loading violations: \(error)")
                    }
                }
            }
        }
        .onChange(of: dependencies.workspaceManager.currentWorkspace) { oldValue, newWorkspace in
            // Reload violations when workspace changes
            if let workspace = newWorkspace {
                Task {
                    do {
                        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
                    } catch {
                        print("Error loading violations: \(error)")
                    }
                }
            } else {
                // Clear violations when workspace is closed
                Task {
                    viewModel.clearViolations()
                }
            }
        }
        .onChange(of: viewModel.filteredViolations) {
            // Clear selection if selected violation is no longer in filtered list
            if let selectedId = selectedViolationId,
               !viewModel.filteredViolations.contains(where: { $0.id == selectedId }) {
                self.selectedViolationId = nil
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        try? await viewModel.refreshViolations()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                if !viewModel.selectedViolationIds.isEmpty {
                    Menu {
                        Button {
                            Task {
                                try? await viewModel.suppressSelectedViolations(reason: "Suppressed via Violation Inspector")
                            }
                        } label: {
                            Label("Suppress Selected", systemImage: "eye.slash")
                        }
                        
                        Button {
                            Task {
                                try? await viewModel.resolveSelectedViolations()
                            }
                        } label: {
                            Label("Mark as Resolved", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var violationListView: some View {
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
                List(selection: $selectedViolationId) {
                    ForEach(viewModel.filteredViolations, id: \.id) { violation in
                        ViolationListItem(violation: violation)
                            .tag(violation.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
    
    private var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search violations...", text: $viewModel.searchText)
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
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Severity", systemImage: "exclamationmark.triangle")
                    }
                    
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
    
    private var statisticsView: some View {
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
    
    private var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)
            
            Text("Analyzing Workspace")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Running SwiftLint to detect violations...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("This may take a few minutes for large projects")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Violations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No violations match your current filters.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
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
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select a Violation")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a violation from the list to view details")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

struct StatisticBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

