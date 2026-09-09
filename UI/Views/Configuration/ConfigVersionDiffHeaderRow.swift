//
//  ConfigVersionDiffHeaderRow.swift
//  SwiftLintRuleStudio
//
//  The two pieces of the version-history diff pane that do not read the view model.
//

import SwiftUI

/// Shown until two backups are picked.
///
/// Reads only its own `@ScaledMetric`, so every change to the view model leaves it alone.
struct ConfigVersionHistoryEmptyState: View {
    @ScaledMetric(relativeTo: .title) private var iconSizeSmall: CGFloat = 36

    var body: some View {
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

/// The two backup timestamps a comparison is between.
///
/// Takes the two formatted dates rather than the view model, so it does not rebuild when anything
/// else on the model changes — the backup list, the restore confirmation, the load state.
struct ConfigVersionDiffHeaderRow: View {
    let before: String?
    let after: String?

    var body: some View {
        HStack {
            if let before {
                Label(before, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let after {
                Label(after, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}
