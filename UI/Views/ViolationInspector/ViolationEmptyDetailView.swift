//
//  ViolationEmptyDetailView.swift
//  SwiftLintRuleStudio
//

import SwiftUI

/// The detail panel's prompt when no violation is selected.
struct ViolationEmptyDetailView: View {
    @ScaledMetric(relativeTo: .title) private var iconSizeMedium: CGFloat = 48

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: iconSizeMedium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Select a Violation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select a violation from the list to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
