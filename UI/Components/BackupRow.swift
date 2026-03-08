//
//  BackupRow.swift
//  SwiftLintRuleStudio
//
//  Row view for a single configuration backup entry
//

import SwiftUI

struct BackupRow: View {
    let backup: ConfigBackup
    let isSelected: Bool
    let isComparison: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.formattedDate)
                        .font(.body)
                        .fontWeight(isSelected || isComparison ? .bold : .regular)

                    Text(backup.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("First selection")
                } else if isComparison {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Second selection")
                }
            }
            .padding(.vertical, 2)
            .background(
                (isSelected || isComparison) ? Color.accentColor.opacity(0.1) : Color.clear
            )
            .clipShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Restore This Version", systemImage: "arrow.uturn.backward", action: onRestore)
        }
    }
}
