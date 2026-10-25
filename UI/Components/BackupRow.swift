//
//  BackupRow.swift
//  SwiftLintRuleStudio
//
//  Row view for a single configuration backup entry
//

import SwiftLintRuleStudioCore
import SwiftUI

struct BackupRow: View {
    let backup: ConfigBackup
    let isSelected: Bool
    let isComparison: Bool
    /// The configuration as it is now, rather than a backup: nothing to restore.
    var isCurrent = false
    let onSelect: () -> Void
    let onRestore: () -> Void

    private var subtitle: String {
        isCurrent ? "Your .swiftlint.yml as it is now · \(backup.formattedSize)" : backup.formattedSize
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrent ? "Current" : backup.formattedDate)
                        .font(.body)
                        .fontWeight(isSelected || isComparison ? .bold : .regular)

                    Text(subtitle)
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
            if !isCurrent {
                Button("Restore This Version", systemImage: "arrow.uturn.backward", action: onRestore)
            }
        }
    }
}

#Preview {
    let backup = ConfigBackup(
        id: "preview",
        path: URL(filePath: "/tmp/.swiftlint.yml"),
        timestamp: Date(),
        fileSize: 2_340
    )
    return VStack(spacing: 0) {
        BackupRow(
            backup: backup,
            isSelected: false,
            isComparison: false,
            onSelect: {},
            onRestore: {}
        )
        BackupRow(
            backup: backup,
            isSelected: true,
            isComparison: false,
            onSelect: {},
            onRestore: {}
        )
    }
    .padding()
}
