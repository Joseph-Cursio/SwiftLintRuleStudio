//
//  LegacyBackupsNotice.swift
//  SwiftLintRuleStudio
//
//  Version History's offer to move backups an earlier version left in the project folder.
//

import SwiftUI

/// Shown while backups from before the app kept them in its own folder still sit in the
/// project folder, one untracked file per save. Moving them is offered, never done for the user:
/// a project might track them in git.
struct LegacyBackupsNotice: View {
    let count: Int
    let onMove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 backup is in the project folder" : "\(count) backups are in the project folder")
                    .font(.subheadline.weight(.semibold))
                Text("Saved before backups moved to the app's own folder. Moving them out keeps "
                    + "every one of them here and sends the files in the project to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Move Out of Project", action: onMove)
                .accessibilityIdentifier("ConfigHistoryMoveLegacyBackupsButton")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ConfigHistoryLegacyBackupsNotice")
    }
}
