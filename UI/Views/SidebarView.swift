//
//  SidebarView.swift
//  SwiftLintRuleStudio
//
//  Navigation sidebar listing all app sections
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Sidebar sections

// Each section depends on fewer of the sidebar's inputs than the sidebar does, so SwiftUI can skip
// it when the others change. `SidebarView` re-renders on `selection`, `dependencies` and
// `ruleRegistry`; `AnalysisSection` and `ConfigurationSection` depend on none of them.
//
// That these can be extracted at all was measured rather than assumed — see
// `TagResolutionMeasurementTests`. A `.tag()` applied inside an extracted `View` still resolves
// against the enclosing `List(selection:)`, which is what makes each of these safe to move.

/// The current workspace's name and path, or nothing when none is open.
private struct WorkspaceInfoSection: View {
    let workspace: Workspace?

    var body: some View {
        if let workspace {
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
}

/// Rules, violations and export. Takes the rule count rather than the registry.
private struct WorkspaceNavigationSection: View {
    let ruleCount: Int

    var body: some View {
        SwiftUI.Section("Workspace") {
            Label("Rules", systemImage: "list.bullet.rectangle")
                .badge(max(ruleCount, 0))
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
}

/// Dashboard, audit and version check. Depends on nothing.
private struct AnalysisSection: View {
    var body: some View {
        SwiftUI.Section("Analysis") {
            Label("Dashboard", systemImage: "chart.bar").tag(AppSection.dashboard)
            Label("Disabled Rule Audit", systemImage: "checklist").tag(AppSection.ruleAudit)
                .accessibilityIdentifier("SidebarRuleAuditLink")
            Label("Version Check", systemImage: "checkmark.shield").tag(AppSection.versionCheck)
                .accessibilityIdentifier("SidebarVersionCheckLink")
        }
    }
}

/// The configuration destinations. Depends on nothing.
private struct ConfigurationSection: View {
    var body: some View {
        SwiftUI.Section("Configuration") {
            Label("Config Map", systemImage: "map").tag(AppSection.configMap)
                .accessibilityIdentifier("SidebarConfigMapLink")
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

struct SidebarView: View {
    @Binding var selection: AppSection?
    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry

    var body: some View {
        List(selection: $selection) {
            WorkspaceInfoSection(workspace: dependencies.workspaceManager.currentWorkspace)
            WorkspaceNavigationSection(ruleCount: ruleRegistry.rules.count)
            AnalysisSection()
            ConfigurationSection()
        }
        .listStyle(.sidebar)
    }
}
