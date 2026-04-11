//
//  SidebarView.swift
//  SwiftLintRuleStudio
//
//  Navigation sidebar listing all app sections
//

import SwiftUI
import SwiftLintRuleStudioCore

struct SidebarView: View {
    @Binding var selection: AppSection?
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry

    var body: some View {
        List(selection: $selection) {
            workspaceInfoSection
            workspaceNavigationSection
            analysisSection
            configurationSection
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var workspaceInfoSection: some View {
        if let workspace = dependencies.workspaceManager.currentWorkspace {
            SwiftUI.Section("Workspace") {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(workspace.name)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
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
    }

    private var workspaceNavigationSection: some View {
        SwiftUI.Section("Workspace") {
            Label("Rules", systemImage: "list.bullet.rectangle")
                .badge(max(ruleRegistry.rules.count, 0))
                .tag(AppSection.rules)
                .accessibilityIdentifier("SidebarRulesLink")
            Label("Enabled Rule Violations", systemImage: "exclamationmark.triangle")
                .tag(AppSection.violations)
                .accessibilityIdentifier("SidebarViolationsLink")
            Label("Export Report", systemImage: "square.and.arrow.up")
                .tag(AppSection.exportReport)
                .accessibilityIdentifier("SidebarExportReportLink")
        }
    }

    private var analysisSection: some View {
        SwiftUI.Section("Analysis") {
            Label("Dashboard", systemImage: "chart.bar").tag(AppSection.dashboard)
            Label("Disabled Rule Audit", systemImage: "checklist").tag(AppSection.ruleAudit)
                .accessibilityIdentifier("SidebarRuleAuditLink")
            Label("Version Check", systemImage: "checkmark.shield").tag(AppSection.versionCheck)
                .accessibilityIdentifier("SidebarVersionCheckLink")
        }
    }

    private var configurationSection: some View {
        SwiftUI.Section("Configuration") {
            Label("Version History", systemImage: "clock.arrow.circlepath").tag(AppSection.versionHistory)
                .accessibilityIdentifier("SidebarVersionHistoryLink")
            Label("Compare Configs", systemImage: "arrow.left.arrow.right").tag(AppSection.compareConfigs)
                .accessibilityIdentifier("SidebarCompareConfigsLink")
            Label("Import Config", systemImage: "square.and.arrow.down").tag(AppSection.importConfig)
                .accessibilityIdentifier("SidebarImportConfigLink")
            Label("Branch Diff", systemImage: "arrow.triangle.branch").tag(AppSection.branchDiff)
                .accessibilityIdentifier("SidebarBranchDiffLink")
            Label("Migration", systemImage: "arrow.up.circle").tag(AppSection.migration)
                .accessibilityIdentifier("SidebarMigrationLink")
        }
    }
}
