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
    @State private var didApplyUITestOverrides = false
    
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
                            .foregroundStyle(.secondary)
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
            if !didApplyUITestOverrides {
                didApplyUITestOverrides = true
                applyUITestOverrides()
            }
        }
        .alert("Error Loading Rules", isPresented: TestGuard.alertBinding($showError)) {
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

    private func applyUITestOverrides() {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("-uiTesting") else { return }

        let environment = processInfo.environment
        if environment["UI_TEST_SKIP_ONBOARDING"] == "1" {
            dependencies.onboardingManager.completeOnboarding()
        }

        if environment["UI_TEST_WORKSPACE"] == "1" {
            do {
                let workspaceURL = try createUITestWorkspace()
                try dependencies.workspaceManager.openWorkspace(at: workspaceURL)
            } catch {
                print("UI test workspace setup failed: \(error)")
            }
        }
    }

    private func createUITestWorkspace() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        let content = """
        import Foundation

        struct UITestStruct {
            let value: String
        }
        """
        try content.write(to: swiftFile, atomically: true, encoding: .utf8)
        return tempDir
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
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text(workspace.name)
                                .font(.headline)
                        }
                        Text(workspace.path.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                RuleBrowserView(ruleRegistry: dependencies.ruleRegistry)
            } label: {
                Label("Rules", systemImage: "list.bullet.rectangle")
            }
            .accessibilityIdentifier("SidebarRulesLink")
            
            NavigationLink {
                ViolationInspectorView()
            } label: {
                Label("Violations", systemImage: "exclamationmark.triangle")
            }
            .accessibilityIdentifier("SidebarViolationsLink")
            
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
            .accessibilityIdentifier("SidebarSafeRulesLink")

            NavigationLink {
                ConfigVersionHistoryView(
                    service: dependencies.configVersionHistoryService,
                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                )
            } label: {
                Label("Version History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("SidebarVersionHistoryLink")

            NavigationLink {
                ConfigComparisonView(
                    service: dependencies.configComparisonService,
                    currentWorkspace: dependencies.workspaceManager.currentWorkspace
                )
            } label: {
                Label("Compare Configs", systemImage: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("SidebarCompareConfigsLink")

            NavigationLink {
                VersionCompatibilityView(
                    checker: dependencies.versionCompatibilityChecker,
                    swiftLintCLI: dependencies.swiftLintCLI,
                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                )
            } label: {
                Label("Version Check", systemImage: "checkmark.shield")
            }
            .accessibilityIdentifier("SidebarVersionCheckLink")

            NavigationLink {
                ConfigImportView(
                    importService: dependencies.configImportService,
                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                )
            } label: {
                Label("Import Config", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("SidebarImportConfigLink")

            NavigationLink {
                GitBranchDiffView(
                    service: dependencies.gitBranchDiffService,
                    workspacePath: dependencies.workspaceManager.currentWorkspace?.path
                )
            } label: {
                Label("Branch Diff", systemImage: "arrow.triangle.branch")
            }
            .accessibilityIdentifier("SidebarBranchDiffLink")

            NavigationLink {
                MigrationAssistantView(
                    assistant: dependencies.migrationAssistant,
                    swiftLintCLI: dependencies.swiftLintCLI,
                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                )
            } label: {
                Label("Migration", systemImage: "arrow.up.circle")
            }
            .accessibilityIdentifier("SidebarMigrationLink")
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
