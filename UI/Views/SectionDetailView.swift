//
//  SectionDetailView.swift
//  SwiftLintRuleStudio
//
//  Section detail routing for the main content area
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The detail column for the sidebar's selected section. `ContentView` owns the selection, the
/// search text, the selected rule and the rule browser's view model; this reads and writes
/// them through what it is handed.
struct SectionDetailView: View {
    @Binding var selection: AppSection?
    @Binding var searchText: String
    @Binding var selectedRuleId: String?
    let ruleBrowserViewModel: RuleBrowserViewModel?

    @Environment(\.ruleRegistry) private var ruleRegistry: RuleRegistry
    @Environment(\.dependencies) private var dependencies: DependencyContainer

    @ViewBuilder
    var body: some View {
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

        case .exportReport:
            ExportReportView()

        case .dashboard:
            DashboardView { preset in
                // The rule browser restores this search when it appears, over the preset.
                searchText = ""
                ruleBrowserViewModel?.applyPreset(preset)
                selection = .rules
            }

        case .ruleAudit:
            RuleAuditView()

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

        case .configMap:
            ConfigMapView(
                workspacePath: dependencies.workspaceManager.currentWorkspace?.path,
                builtInRuleIdentifiers: Set(ruleRegistry.rules.map(\.id))
            )

        case .none:
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
    }
}
