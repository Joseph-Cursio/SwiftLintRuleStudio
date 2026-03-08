//
//  SidebarView.swift
//  SwiftLintRuleStudio
//
//  Navigation sidebar listing all app sections
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection?
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry

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
            SwiftUI.Section("Workspace") {
                Label("Rules", systemImage: "list.bullet.rectangle")
                    .badge(max(ruleRegistry.rules.count, 0))
                    .tag(AppSection.rules)
                    .accessibilityIdentifier("SidebarRulesLink")
                Label("Violations", systemImage: "exclamationmark.triangle").tag(AppSection.violations)
                    .accessibilityIdentifier("SidebarViolationsLink")
            }

            SwiftUI.Section("Analysis") {
                Label("Dashboard", systemImage: "chart.bar").tag(AppSection.dashboard)
                Label("Safe Rules", systemImage: "checkmark.circle.badge.questionmark").tag(AppSection.safeRules)
                    .accessibilityIdentifier("SidebarSafeRulesLink")
                Label("Version Check", systemImage: "checkmark.shield").tag(AppSection.versionCheck)
                    .accessibilityIdentifier("SidebarVersionCheckLink")
            }

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
        .listStyle(.sidebar)
    }
}
