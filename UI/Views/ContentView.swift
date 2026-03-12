//
//  ContentView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var didApplyUITestOverrides = false
    
    @State private var selection: AppSection? = .rules
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""
    @State private var showWorkspacePicker = false
    
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
                NavigationSplitView(columnVisibility: $columnVisibility) {
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
                                    externalSearchText: $searchText
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
                    // Title shown in the middle of the window titlebar
                    ToolbarItem(placement: .principal) {
                        Text("SwiftLint Rule Studio")
                            .font(.headline)
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
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        if let workspace = dependencies.workspaceManager.currentWorkspace {
                            Label(workspace.path.path, systemImage: "folder")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if ruleRegistry.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                        } else if !ruleRegistry.rules.isEmpty {
                            Text("\(ruleRegistry.rules.count) rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(.bar)
                }
                .navigationSubtitle(dependencies.workspaceManager.currentWorkspace?.name ?? "")
                .fileImporter(
                    isPresented: $showWorkspacePicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        try? dependencies.workspaceManager.openWorkspace(at: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openWorkspaceRequested)) { _ in
                    showWorkspacePicker = true
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let url: URL?
                        if let nsURL = item as? NSURL {
                            url = nsURL as URL
                        } else if let data = item as? Data {
                            url = URL(dataRepresentation: data, relativeTo: nil)
                        } else {
                            url = nil
                        }
                        guard let dropURL = url else { return }
                        Task { @MainActor in
                            try? dependencies.workspaceManager.openWorkspace(at: dropURL)
                        }
                    }
                    return true
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

}

private extension ContentView {
    func applyUITestOverrides() {
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

    func createUITestWorkspace() throws -> URL {
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
        .environment(\.ruleRegistry, ruleRegistry)
        .environment(\.dependencies, container)
}
