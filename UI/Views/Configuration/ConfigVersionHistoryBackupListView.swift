//
//  ConfigVersionHistoryBackupListView.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

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

            if viewModel.selectedBackup != nil, viewModel.comparisonBackup == nil {
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
