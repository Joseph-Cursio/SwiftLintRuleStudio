//
//  ConfigErrorCard.swift
//  SwiftLintRuleStudio
//
//  Standard error card shared across configuration views.
//

import SwiftUI

/// A standard error card displaying an error's localized description.
/// Shared across the configuration views (import, version compatibility,
/// git branch diff) so they present errors identically.
struct ConfigErrorCard: View {
    let error: Error

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}
