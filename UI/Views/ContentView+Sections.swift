//
//  ContentView+Sections.swift
//  SwiftLintRuleStudio
//
//  Section detail routing for the main content area
//

import SwiftUI
import SwiftLintRuleStudioCore

extension ContentView {
    @ViewBuilder
    var sectionDetailView: some View {
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
            Text("Dashboard")
                .navigationTitle("Dashboard")
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
        case .none:
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
    }
}
