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
    @State private var selectedRuleId: String?
    @State private var ruleBrowserViewModel: RuleBrowserViewModel?
    @State private var showWorkspacePicker = false

    var body: some View {
        Group {
            if !dependencies.onboardingManager.hasCompletedOnboarding {
                OnboardingView(
                    onboardingManager: dependencies.onboardingManager,
                    workspaceManager: dependencies.workspaceManager,
                    swiftLintCLI: dependencies.swiftLintCLI
                )
            } else if dependencies.workspaceManager.currentWorkspace == nil {
                WorkspaceSelectionView(workspaceManager: dependencies.workspaceManager)
            } else {
                mainNavigationView
            }
        }
        .task { await loadRulesOnLaunch() }
        .onChange(of: dependencies.workspaceManager.currentWorkspace?.id) {
            dependencies.workspaceManager.checkConfigFileExists()
        }
        .onAppear(perform: handleOnAppear)
        .alert("Error Loading Rules", isPresented: TestGuard.alertBinding($showError)) {
            errorAlertActions
        } message: {
            Text(errorMessage ?? "Unknown error occurred while loading SwiftLint rules.")
        }
    }

    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationTitle("SwiftLint Rule Studio")
                .listStyle(.sidebar)
        } detail: {
            detailContent
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { statusBar }
        .navigationSubtitle(dependencies.workspaceManager.currentWorkspace?.name ?? "")
        .fileImporter(
            isPresented: $showWorkspacePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onReceive(NotificationCenter.default.publisher(for: .openWorkspaceRequested)) { _ in
            showWorkspacePicker = true
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
        .toolbarTitleMenu { titleMenuContent }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            if dependencies.workspaceManager.configFileMissing {
                ConfigRecommendationView(workspaceManager: dependencies.workspaceManager)
                    .padding()
            }
            sectionDetailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sectionDetailView: some View {
        switch selection {
        case .rules:
            if let ruleBrowserViewModel {
                RuleBrowserView(
                    viewModel: ruleBrowserViewModel,
                    externalSearchText: $searchText,
                    selectedRuleId: $selectedRuleId
                )
            }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("SwiftLint Rule Studio")
                .font(.headline)
        }
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

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let workspace = dependencies.workspaceManager.currentWorkspace {
                Label(workspace.path.path(), systemImage: "folder")
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

    @ViewBuilder
    private var titleMenuContent: some View {
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

    @ViewBuilder
    private var errorAlertActions: some View {
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
    }

    private func loadRulesOnLaunch() async {
        do {
            _ = try await ruleRegistry.loadRules()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleOnAppear() {
        dependencies.workspaceManager.checkConfigFileExists()
        if ruleBrowserViewModel == nil {
            ruleBrowserViewModel = RuleBrowserViewModel(ruleRegistry: ruleRegistry)
        }
        if !didApplyUITestOverrides {
            didApplyUITestOverrides = true
            applyUITestOverrides()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            do {
                try dependencies.workspaceManager.openWorkspace(at: url)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task {
            guard let item = try? await provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier
            ),
                  let data = item as? Data,
                  let dropURL = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            do {
                try dependencies.workspaceManager.openWorkspace(at: dropURL)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        return true
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
            if let workspaceURL = try? createUITestWorkspace() {
                try? dependencies.workspaceManager.openWorkspace(at: workspaceURL)
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
