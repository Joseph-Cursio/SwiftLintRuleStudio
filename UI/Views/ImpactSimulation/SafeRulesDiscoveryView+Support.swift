//
//  SafeRulesDiscoveryView+Support.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
import SwiftLintRuleStudioCore

struct DiscoveryProgress {
    let current: Int
    let total: Int
    let ruleId: String
}

struct SafeRuleRow: View {
    let ruleResult: RuleImpactResult
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
        HStack {
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .accessibilityLabel(isSelected ? "Deselect rule" : "Select rule")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(ruleResult.ruleId)
                    .font(.headline)

                Text("Zero violations • Safe to enable")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
