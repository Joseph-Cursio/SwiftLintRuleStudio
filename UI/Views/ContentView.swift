//
//  ContentView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let violationInspectorRefreshRequested = Notification.Name("ViolationInspectorRefreshRequested")
}

enum AppSection: Hashable {
    case rules
    case violations
    case dashboard
    case safeRules
    case versionHistory
    case compareConfigs
    case versionCheck
    case importConfig
    case branchDiff
    case migration
}

struct ContentView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @EnvironmentObject var dependencies: DependencyContainer
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var didApplyUITestOverrides = false
    
    @State private var selection: AppSection? = .rules
    @State private var searchText: String = ""
    @State private var viewMode: Int = 0
    
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
                NavigationSplitView {
                    SidebarView(selection: $selection)
                        .navigationTitle("SwiftLint Rule Studio")
                        .listStyle(.sidebar)
                } detail: {
                    VStack(spacing: 0) {
                        // Show config recommendation if config file is missing
                        if dependencies.workspaceManager.configFileMissing {
                            ConfigRecommendationView(workspaceManager: dependencies.workspaceManager)
                                .padding()
                        }

                        Group {
                            switch selection {
                            case .rules:
                                RuleBrowserView(
                                    ruleRegistry: dependencies.ruleRegistry,
                                    externalSearchText: $searchText,
                                    externalViewMode: $viewMode
                                )
                            case .violations:
                                ViolationInspectorView()
                            case .dashboard:
                                Text("Dashboard")
                                    .navigationTitle("Dashboard")
                            case .safeRules:
                                SafeRulesDiscoveryView()
                            case .versionHistory:
                                ConfigVersionHistoryView(
                                    service: dependencies.configVersionHistoryService,
                                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                                )
                            case .compareConfigs:
                                ConfigComparisonView(
                                    service: dependencies.configComparisonService,
                                    currentWorkspace: dependencies.workspaceManager.currentWorkspace
                                )
                            case .versionCheck:
                                VersionCompatibilityView(
                                    checker: dependencies.versionCompatibilityChecker,
                                    swiftLintCLI: dependencies.swiftLintCLI,
                                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                                )
                            case .importConfig:
                                ConfigImportView(
                                    importService: dependencies.configImportService,
                                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                                )
                            case .branchDiff:
                                GitBranchDiffView(
                                    service: dependencies.gitBranchDiffService,
                                    workspacePath: dependencies.workspaceManager.currentWorkspace?.path
                                )
                            case .migration:
                                MigrationAssistantView(
                                    assistant: dependencies.migrationAssistant,
                                    swiftLintCLI: dependencies.swiftLintCLI,
                                    configPath: dependencies.workspaceManager.currentWorkspace?.configPath
                                )
                            case .none:
                                Text("Select a section")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
                .toolbar {
#if os(macOS)
                    ToolbarItem(placement: .navigation) {
                        Button {
                            let selector = #selector(NSSplitViewController.toggleSidebar(_:))
                            NSApp.keyWindow?.firstResponder?.tryToPerform(selector, with: nil)
                        } label: {
                            Image(systemName: "sidebar.left")
                                .accessibilityHidden(true)
                        }
                        .help("Toggle Sidebar")
                    }
#endif

                    // Title shown in the middle of the window titlebar
                    ToolbarItem(placement: .principal) {
                        Text("SwiftLint Rule Studio")
                            .font(.headline)
                    }

                    // Context-aware controls: only show in Rules section
                    ToolbarItem(placement: .automatic) {
                        if selection == .rules {
                            Picker("", selection: $viewMode) {
                                Text("List").tag(0)
                                Text("Grid").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .help("Change View Mode")
                            .accessibilityIdentifier("ContentViewViewModePicker")
                        }
                    }

                    // Context-aware search: only show in Rules section (RuleBrowserView handles its own filters)
                    ToolbarItem(placement: .automatic) {
                        if selection == .rules {
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
                                .help("Search rules")
                        }
                    }

                    // Primary actions on the trailing side, vary by section
                    ToolbarItemGroup(placement: .primaryAction) {
                        if selection == .rules {
                            Button {
                                Task { _ = try? await ruleRegistry.loadRules() }
                            } label: {
                                Label("Reload Rules", systemImage: "arrow.clockwise")
                            }
                            .help("Reload SwiftLint rules")
                            .accessibilityIdentifier("ContentViewReloadRulesButton")
                        } else if selection == .violations {
                            Button {
                                NotificationCenter.default.post(name: .violationInspectorRefreshRequested, object: nil)
                            } label: {
                                Label("Refresh Violations", systemImage: "arrow.clockwise")
                            }
                            .help("Refresh violations for current workspace")
                            .accessibilityIdentifier("ContentViewRefreshViolationsButton")
                        } else if selection == .versionHistory {
                            Button {
                                // Optionally post a notification or call into a service to refresh history
                                // NotificationCenter.default.post(name: .configHistoryRefreshRequested, object: nil)
                            } label: {
                                Label("Refresh History", systemImage: "arrow.clockwise")
                            }
                            .help("Refresh configuration version history")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        if let workspace = dependencies.workspaceManager.currentWorkspace {
                            Label(workspace.path.path, systemImage: "folder")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(.bar)
                }
                .toolbarTitleMenu {
                    Button("Rules") { selection = .rules }
                    Button("Violations") { selection = .violations }
                    Button("Dashboard") { selection = .dashboard }
                    Button("Safe Rules") { selection = .safeRules }
                    Button("Version History") { selection = .versionHistory }
                    Button("Compare Configs") { selection = .compareConfigs }
                    Button("Version Check") { selection = .versionCheck }
                    Button("Import Config") { selection = .importConfig }
                    Button("Branch Diff") { selection = .branchDiff }
                    Button("Migration") { selection = .migration }
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
    @Binding var selection: AppSection?
    @EnvironmentObject var dependencies: DependencyContainer
    @EnvironmentObject var ruleRegistry: RuleRegistry
    
    var body: some View {
        List(selection: $selection) {
            // Workspace Info Section
            if let workspace = dependencies.workspaceManager.currentWorkspace {
                SwiftUI.Section("Workspace") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text(workspace.name)
                                .font(.headline)
                        }
                        Text(workspace.path.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Navigation Items
            SwiftUI.Section("Tools") {
                Label("Rules", systemImage: "list.bullet.rectangle")
                    .badge(max(ruleRegistry.rules.count, 0))
                    .tag(AppSection.rules)
                    .accessibilityIdentifier("SidebarRulesLink")
                Label("Violations", systemImage: "exclamationmark.triangle").tag(AppSection.violations)
                    .accessibilityIdentifier("SidebarViolationsLink")
                Label("Dashboard", systemImage: "chart.bar").tag(AppSection.dashboard)
                Label("Safe Rules", systemImage: "checkmark.circle.badge.questionmark").tag(AppSection.safeRules)
                    .accessibilityIdentifier("SidebarSafeRulesLink")
                Label("Version History", systemImage: "clock.arrow.circlepath").tag(AppSection.versionHistory)
                    .accessibilityIdentifier("SidebarVersionHistoryLink")
                Label("Compare Configs", systemImage: "arrow.left.arrow.right").tag(AppSection.compareConfigs)
                    .accessibilityIdentifier("SidebarCompareConfigsLink")
                Label("Version Check", systemImage: "checkmark.shield").tag(AppSection.versionCheck)
                    .accessibilityIdentifier("SidebarVersionCheckLink")
                Label("Import Config", systemImage: "square.and.arrow.down").tag(AppSection.importConfig)
                    .accessibilityIdentifier("SidebarImportConfigLink")
                Label("Branch Diff", systemImage: "arrow.triangle.branch").tag(AppSection.branchDiff)
                    .accessibilityIdentifier("SidebarBranchDiffLink")
                Label("Migration", systemImage: "arrow.up.circle").tag(AppSection.migration)
                    .accessibilityIdentifier("SidebarMigrationLink")
            }
        }
        .listStyle(.sidebar)
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
