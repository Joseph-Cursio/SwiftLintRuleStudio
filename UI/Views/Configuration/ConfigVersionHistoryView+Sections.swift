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
                before: viewModel.selectedBackup?.formattedDate,
                after: viewModel.comparisonBackup?.formattedDate
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
                beforeLabel: "Before — \(viewModel.selectedBackup?.formattedDate ?? "Unknown")",
                afterLabel: "After — \(viewModel.comparisonBackup?.formattedDate ?? "Unknown")"
            )
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
                ForEach(viewModel.backups) { backup in
                    BackupRow(
                        backup: backup,
                        isSelected: viewModel.selectedBackup?.id == backup.id,
                        isComparison: viewModel.comparisonBackup?.id == backup.id,
                        onSelect: { viewModel.selectForComparison(backup) },
                        onRestore: { viewModel.confirmRestore(backup) }
                    )
                }
            }
            .listStyle(.sidebar)

            if viewModel.selectedBackup != nil && viewModel.comparisonBackup == nil {
                Text("Select another backup to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

// MARK: - File marker (satisfies file_name lint rule)

extension ConfigVersionHistoryView {}
