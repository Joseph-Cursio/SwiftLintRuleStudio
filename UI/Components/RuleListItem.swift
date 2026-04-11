//
//  RuleListItem.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI
import SwiftLintRuleStudioCore
import LintStudioUI
import LintStudioCore

struct RuleListItem: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Rule name and identifier
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rule.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(rule.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Description
                Text(rule.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Category badge and opt-in indicator
                HStack(spacing: 8) {
                    CategoryBadge(
                        category: rule.category,
                        color: RuleCategoryColors.color(for: rule.category)
                    )

                    if rule.isOptIn {
                        Label("Opt-In", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if rule.isEnabled {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if rule.isEnabled {
            return .green
        } else if rule.isOptIn {
            return .orange
        } else {
            return .gray
        }
    }
}

#Preview {
    let rule = Rule(
        id: "force_cast",
        name: "Force Cast",
        description: "Force casts should be avoided.",
        category: .lint,
        isOptIn: false,
        severity: nil,
        parameters: nil,
        triggeringExamples: [],
        nonTriggeringExamples: [],
        documentation: nil,
        isEnabled: true,
        supportsAutocorrection: false,
        minimumSwiftVersion: nil,
        defaultSeverity: nil,
        markdownDocumentation: nil
    )

    return List {
        RuleListItem(rule: rule)
        RuleListItem(rule: Rule(
            id: "opt_in_rule",
            name: "Opt-In Rule",
            description: "This is an opt-in rule that must be explicitly enabled.",
            category: .style,
            isOptIn: true,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        ))
    }
    .frame(width: 400, height: 200)
}
