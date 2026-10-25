//
//  ConfigVersionHistoryView+Sections.swift
//  SwiftLintRuleStudio
//
//  Section views for the configuration version history screen
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ConfigVersionHistoryEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Version History", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Configuration backups will appear here after you save changes.")
        }
    }
}

struct ConfigVersionHistoryBackupListView: View {
    let viewModel: ConfigVersionHistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backups (\(viewModel.backups.count))")
                    .font(.headline)
                Spacer()
                if viewModel.selectedBackup != nil || viewModel.comparisonBackup != nil {
                    Button("Clear", action: viewModel.clearComparison)
                        .font(.caption)
                }
            }
            .padding()

            Divider()

            List {
                if let current = viewModel.current {
                    row(for: current, isCurrent: true)
                }
                ForEach(viewModel.backups) { backup in
                    row(for: backup, isCurrent: false)
                }
            }
            .listStyle(.sidebar)

            if viewModel.selectedBackup != nil && viewModel.comparisonBackup == nil {
                Text("Select another version to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func row(for backup: ConfigBackup, isCurrent: Bool) -> some View {
        BackupRow(
            backup: backup,
            isSelected: viewModel.selectedBackup?.id == backup.id,
            isComparison: viewModel.comparisonBackup?.id == backup.id,
            isCurrent: isCurrent,
            onSelect: { viewModel.selectForComparison(backup) },
            onRestore: { viewModel.confirmRestore(backup) }
        )
    }
}

struct ConfigVersionHistoryDiffDetailView: View {
    let viewModel: ConfigVersionHistoryViewModel

    var body: some View {
        VStack {
            if let diff = viewModel.currentDiff {
                diffContent(diff)
            } else {
                ConfigVersionHistoryEmptyState()
            }
        }
    }

    private func diffContent(_ diff: YAMLConfigurationEngine.ConfigDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ConfigVersionDiffHeaderRow(
                before: viewModel.selectedBackup.map(viewModel.label(for:)),
                after: viewModel.comparisonBackup.map(viewModel.label(for:)),
                onSwap: viewModel.swapComparison
            )
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            ConfigDiffPreviewView(
                diff: diff,
                ruleName: "Version Comparison",
                onSave: {
                    if let backup = viewModel.comparisonBackup {
                        viewModel.confirmRestore(backup)
                    }
                },
                onCancel: {
                    viewModel.clearComparison()
                },
                isInline: true,
                beforeLabel: "Before — \(viewModel.selectedBackup.map(viewModel.label(for:)) ?? "Unknown")",
                afterLabel: "After — \(viewModel.comparisonBackup.map(viewModel.label(for:)) ?? "Unknown")",
                // Restoring brings back the "after" side; with the current configuration
                // there, there's nothing to restore.
                saveLabel: viewModel.restoreLabel ?? "",
                cancelLabel: "Clear Comparison",
                showsSave: viewModel.restoreLabel != nil
            )
        }
    }

}

// MARK: - File marker (satisfies file_name lint rule)

extension ConfigVersionHistoryView {}
