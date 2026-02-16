//
//  RuleDetailView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleDetailView: View {
    @StateObject var viewModel: RuleDetailViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dependencies: DependencyContainer
    @State private var showSaveConfirmation = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showImpactSimulation = false
    @State private var impactResult: RuleImpactResult?
    @State var isSimulating = false
    @State private var currentRule: Rule
    @State var violationCount: Int = 0
    @State var isLoadingViolationCount = false
    
    let ruleId: String
    
    // Get the latest rule from registry (may have updated documentation)
    // Made internal for testing
    var rule: Rule {
        dependencies.ruleRegistry.getRule(id: ruleId) ?? currentRule
    }
    
    init(rule: Rule) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        // Create ViewModel - will be updated with workspace config in onAppear
        _viewModel = StateObject(wrappedValue: RuleDetailViewModel(rule: rule))
    }

    init(rule: Rule, viewModel: RuleDetailViewModel) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerView
                
                Divider()
                
                // Configuration
                configurationView
                
                Divider()
                
                // Description
                descriptionView
                
                Divider()
                
                // Why This Matters (Rationale)
                whyThisMattersView
                
                Divider()
                
                // Violations Count
                violationsCountView
                
                Divider()
                
                // Related Rules
                relatedRulesView
                
                Divider()
                
                // Swift Evolution Links
                swiftEvolutionView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .padding(.horizontal, 20)
        }
        .navigationTitle(rule.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.pendingChanges != nil {
                    Button {
                        viewModel.showPreview()
                    } label: {
                        Label("Preview Changes", systemImage: "eye")
                    }
                    
                    Button {
                        Task {
                            do {
                                try viewModel.saveConfiguration()
                                showSaveConfirmation = true
                            } catch {
                                showError = true
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .onAppear {
            // Update ViewModel with workspace config if available
            if let workspace = dependencies.workspaceManager.currentWorkspace,
               let configPath = workspace.configPath {
                let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
                viewModel.yamlEngine = yamlEngine
                viewModel.workspaceManager = dependencies.workspaceManager
                
                // Load current configuration
                do {
                    try viewModel.loadConfiguration()
                } catch {
                    print("Warning: Failed to load configuration: \(error)")
                }
            }
            
        }
        .task {
            // Fetch rule details if documentation is missing
            guard rule.markdownDocumentation == nil || rule.markdownDocumentation?.isEmpty == true else { return }
            await dependencies.ruleRegistry.fetchRuleDetailsIfNeeded(id: ruleId)
            if let updatedRule = dependencies.ruleRegistry.getRule(id: ruleId) {
                currentRule = updatedRule
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { notification in
            // Reload configuration if this rule was changed
            if let ruleId = notification.userInfo?["ruleId"] as? String,
               ruleId == rule.id {
                try? viewModel.loadConfiguration()
            }
        }
        .id(rule.id) // Force view recreation when rule ID changes
        .onChange(of: dependencies.ruleRegistry.rules) {
            // Update local rule when registry updates
            if let updatedRule = dependencies.ruleRegistry.getRule(id: ruleId) {
                currentRule = updatedRule
            }
        }
        .sheet(isPresented: $viewModel.showDiffPreview) {
            if let diff = viewModel.generateDiff() {
                ConfigDiffPreviewView(diff: diff, ruleName: rule.name) {
                    Task {
                        do {
                            try viewModel.saveConfiguration()
                            viewModel.showDiffPreview = false
                            showSaveConfirmation = true
                        } catch {
                            showError = true
                        }
                    }
                } onCancel: {
                    viewModel.showDiffPreview = false
                }
            }
        }
        .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Rule configuration has been saved to your workspace's .swiftlint.yml file.")
        }
        .alert("Error", isPresented: TestGuard.alertBinding($showError)) {
            Button("OK") {
                viewModel.saveError = nil
            }
        } message: {
            Text(viewModel.saveError?.localizedDescription ?? "An error occurred while saving the configuration.")
        }
        .sheet(isPresented: $showImpactSimulation) {
            if let result = impactResult {
                ImpactSimulationView(
                    ruleId: rule.id,
                    ruleName: rule.name,
                    result: result,
                    onEnable: {
                        viewModel.updateEnabled(true)
                    }
                )
            }
        }
    }
    
    func simulateRule() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }
        
        isSimulating = true
        
        Task {
            do {
                let result = try await dependencies.impactSimulator.simulateRule(
                    ruleId: rule.id,
                    workspace: workspace,
                    baseConfigPath: workspace.configPath,
                    isOptIn: rule.isOptIn
                )
                
                await MainActor.run {
                    impactResult = result
                    isSimulating = false
                    showImpactSimulation = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSimulating = false
                }
            }
        }
    }
    
    private func loadViolationCount() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            violationCount = 0
            return
        }
        
        isLoadingViolationCount = true
        
        Task {
            do {
                let filter = ViolationFilter(ruleIDs: [rule.id], suppressedOnly: false)
                let count = try await dependencies.violationStorage.getViolationCount(
                    filter: filter,
                    workspaceId: workspace.id
                )
                
                await MainActor.run {
                    violationCount = count
                    isLoadingViolationCount = false
                }
            } catch {
                await MainActor.run {
                    violationCount = 0
                    isLoadingViolationCount = false
                }
            }
        }
    }
}
