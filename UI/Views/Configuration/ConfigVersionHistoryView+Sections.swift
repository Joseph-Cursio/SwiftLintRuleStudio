//
//  ConfigVersionHistoryView+Sections.swift
//  SwiftLintRuleStudio
//
//  Section views for the configuration version history screen
//

import SwiftUI
import SwiftLintRuleStudioCore

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

struct ConfigVersionHistoryDiffDetailView: View {
    @ScaledMetric(relativeTo: .title) private var iconSizeSmall: CGFloat = 36

    let viewModel: ConfigVersionHistoryViewModel

    var body: some View {
        VStack {
            if let diff = viewModel.currentDiff {
                diffContent(diff)
            } else {
                emptyStateContent
            }
        }
    }

    private func diffContent(_ diff: YAMLConfigurationEngine.ConfigDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            diffHeaderRow
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

    private var diffHeaderRow: some View {
        HStack {
            if let first = viewModel.selectedBackup {
                Label(first.formattedDate, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let second = viewModel.comparisonBackup {
                Label(second.formattedDate, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: iconSizeSmall))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Select two backups to compare")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
