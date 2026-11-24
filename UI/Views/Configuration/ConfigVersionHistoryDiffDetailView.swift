//
//  ConfigVersionHistoryDiffDetailView.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

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
