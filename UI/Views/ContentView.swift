//
//  ContentView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @EnvironmentObject var dependencies: DependencyContainer
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    var body: some View {
        Group {
            // Always show onboarding if not completed for this session
            if !dependencies.onboardingManager.hasCompletedOnboarding {
                OnboardingView(
                    onboardingManager: dependencies.onboardingManager,
                    workspaceManager: dependencies.workspaceManager,
                    swiftLintCLI: dependencies.swiftLintCLI
                )
            } else if dependencies.workspaceManager.currentWorkspace == nil {
                // Show workspace selection when no workspace is open
                WorkspaceSelectionView(workspaceManager: dependencies.workspaceManager)
            } else {
                // Show main app interface when workspace is open
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    VStack(spacing: 0) {
                        // Show config recommendation if config file is missing
                        if dependencies.workspaceManager.configFileMissing {
                            ConfigRecommendationView(workspaceManager: dependencies.workspaceManager)
                                .padding()
                        }
                        
                        Text("Select a section")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task {
            // Load rules on app launch
            do {
                _ = try await ruleRegistry.loadRules()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                print("Error loading rules: \(error)")
            }
        }
        .onChange(of: dependencies.workspaceManager.currentWorkspace?.id) {
            // Check config file when workspace changes
            dependencies.workspaceManager.checkConfigFileExists()
        }
        .onAppear {
            // Check config file when view appears
            dependencies.workspaceManager.checkConfigFileExists()
        }
        .alert("Error Loading Rules", isPresented: $showError) {
            Button("OK") {
                errorMessage = nil
                showError = false
            }
            Button("Retry") {
                Task {
                    do {
                        _ = try await ruleRegistry.loadRules()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        } message: {
            Text(errorMessage ?? "Unknown error occurred while loading SwiftLint rules.")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var dependencies: DependencyContainer
    
    var body: some View {
        List {
            // Workspace Info Section
            if let workspace = dependencies.workspaceManager.currentWorkspace {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .accessibilityHidden(true)
                            Text(workspace.name)
                                .font(.headline)
                        }
                        Text(workspace.path.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Workspace")
                }
            }
            
            // Navigation Links
            NavigationLink {
                RuleBrowserView()
            } label: {
                Label("Rules", systemImage: "list.bullet.rectangle")
            }
            
            NavigationLink {
                ViolationInspectorView()
            } label: {
                Label("Violations", systemImage: "exclamationmark.triangle")
            }
            
            NavigationLink {
                Text("Dashboard")
                    .navigationTitle("Dashboard")
            } label: {
                Label("Dashboard", systemImage: "chart.bar")
            }
            
            NavigationLink {
                SafeRulesDiscoveryView()
            } label: {
                Label("Safe Rules", systemImage: "checkmark.circle.badge.questionmark")
            }
        }
        .navigationTitle("SwiftLint Rule Studio")
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
    
    return ContentView()
        .environmentObject(ruleRegistry)
        .environmentObject(container)
}
