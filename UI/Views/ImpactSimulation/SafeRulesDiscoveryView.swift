//
//  SafeRulesDiscoveryView.swift
//  SwiftLintRuleStudio
//
//  View for discovering and bulk-enabling safe rules (zero violations)
//

import SwiftUI

struct SafeRulesDiscoveryView: View {
    @EnvironmentObject var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDiscovering = false
    @State private var discoveryProgress: DiscoveryProgress?
    @State private var safeRules: [RuleImpactResult] = []
    @State private var selectedRules: Set<String> = []
    @State private var isEnabling = false
    @State private var showError = false
    @State private var errorMessage: String?

    init() {}

    init(
        safeRules: [RuleImpactResult],
        selectedRules: Set<String> = [],
        isDiscovering: Bool = false,
        discoveryProgress: DiscoveryProgress? = nil
    ) {
        _safeRules = State(initialValue: safeRules)
        _selectedRules = State(initialValue: selectedRules)
        _isDiscovering = State(initialValue: isDiscovering)
        _discoveryProgress = State(initialValue: discoveryProgress)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                
                if isDiscovering {
                    discoveringView
                } else if safeRules.isEmpty && !isDiscovering {
                    emptyStateView
                } else {
                    rulesListView
                }
            }
            .navigationTitle("Safe Rules Discovery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                if !safeRules.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            enableSelectedRules()
                        } label: {
                            if isEnabling {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Enable Selected (\(selectedRules.count))")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedRules.isEmpty || isEnabling)
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                errorMessage = nil
                showError = false
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover Safe Rules")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Find disabled rules that would produce zero violations if enabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                discoverSafeRules()
            } label: {
                Label("Discover Safe Rules", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDiscovering || dependencies.workspaceManager.currentWorkspace == nil)
        }
        .padding()
    }
    
    private var discoveringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
                if let progress = discoveryProgress {
                Text("Analyzing rule \(progress.current) of \(progress.total)")
                    .font(.headline)
                
                Text("Checking: \(progress.ruleId)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .frame(width: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            Text("No Safe Rules Discovered")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Click 'Discover Safe Rules' to analyze disabled rules in your workspace")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var rulesListView: some View {
        VStack(spacing: 0) {
            // Summary
            HStack {
                Text("Found \(safeRules.count) safe rule\(safeRules.count == 1 ? "" : "s")")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    selectedRules = Set(safeRules.map { $0.ruleId })
                } label: {
                    Text("Select All")
                }
                .buttonStyle(.bordered)
                
                Button {
                    selectedRules.removeAll()
                } label: {
                    Text("Deselect All")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Rules list
            List {
                ForEach(safeRules, id: \.ruleId) { ruleResult in
                    SafeRuleRow(
                        ruleResult: ruleResult,
                        isSelected: selectedRules.contains(ruleResult.ruleId)
                    ) {
                        if selectedRules.contains(ruleResult.ruleId) {
                            selectedRules.remove(ruleResult.ruleId)
                        } else {
                            selectedRules.insert(ruleResult.ruleId)
                        }
                    }
                }
            }
        }
    }
    
    private func discoverSafeRules() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }
        
        isDiscovering = true
        safeRules = []
        selectedRules.removeAll()
        
        Task {
            do {
                // Get all disabled rules from registry
                let allRules = dependencies.ruleRegistry.rules
                let disabledRules = allRules.filter { !$0.isEnabled }
                let disabledRuleIds = disabledRules.map { $0.id }
                
                guard !disabledRuleIds.isEmpty else {
                    await MainActor.run {
                        isDiscovering = false
                    }
                    return
                }
                
                // Find safe rules
                let safeRuleIds = try await dependencies.impactSimulator.findSafeRules(
                    workspace: workspace,
                    baseConfigPath: workspace.configPath,
                    disabledRuleIds: disabledRuleIds
                ) { current, total, ruleId in
                    Task { @MainActor in
                        discoveryProgress = DiscoveryProgress(current: current, total: total, ruleId: ruleId)
                    }
                }
                
                // Get full results for safe rules
                var results: [RuleImpactResult] = []
                for ruleId in safeRuleIds {
                    let result = try await dependencies.impactSimulator.simulateRule(
                        ruleId: ruleId,
                        workspace: workspace,
                        baseConfigPath: workspace.configPath
                    )
                    results.append(result)
                }
                
                await MainActor.run {
                    safeRules = results
                    selectedRules = Set(safeRuleIds) // Select all by default
                    isDiscovering = false
                    discoveryProgress = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isDiscovering = false
                    discoveryProgress = nil
                }
            }
        }
    }
    
    private func enableSelectedRules() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace,
              let configPath = workspace.configPath else {
            return
        }
        
        isEnabling = true
        
        Task {
            do {
                let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
                try yamlEngine.load()
                var config = yamlEngine.getConfig()
                Self.applyEnableRules(config: &config, ruleIds: Array(selectedRules))
                
                try yamlEngine.save(config: config, createBackup: true)
                
                // Post notification
                NotificationCenter.default.post(
                    name: .ruleConfigurationDidChange,
                    object: nil,
                    userInfo: ["ruleIds": Array(selectedRules)]
                )
                
                await MainActor.run {
                    isEnabling = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isEnabling = false
                }
            }
        }
    }

    static func applyEnableRules(
        config: inout YAMLConfigurationEngine.YAMLConfig,
        ruleIds: [String]
    ) {
        for ruleId in ruleIds {
            if config.rules[ruleId] == nil {
                config.rules[ruleId] = RuleConfiguration(enabled: true)
            } else {
                if var ruleConfig = config.rules[ruleId] {
                    ruleConfig.enabled = true
                    config.rules[ruleId] = ruleConfig
                }
            }
            
            if var disabledRules = config.disabledRules {
                disabledRules.removeAll { $0 == ruleId }
                config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
            }
        }
    }
}

struct DiscoveryProgress {
    let current: Int
    let total: Int
    let ruleId: String
}

struct SafeRuleRow: View {
    let ruleResult: RuleImpactResult
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .accessibilityLabel(isSelected ? "Deselect rule" : "Select rule")
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(ruleResult.ruleId)
                    .font(.headline)
                
                Text("Zero violations • Safe to enable")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            onToggle()
        }
    }
}

#Preview {
    SafeRulesDiscoveryView()
        .environmentObject(DependencyContainer())
}
