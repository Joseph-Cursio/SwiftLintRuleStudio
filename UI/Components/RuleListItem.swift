//
//  RuleListItem.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import LintStudioCore
import LintStudioUI
import SwiftLintRuleStudioCore
import SwiftUI

struct RuleListItem: View {
    let rule: Rule
    @Environment(\.appCapabilities) private var capabilities: Set<AppCapability>

    private var isUnavailable: Bool {
        rule.isUnavailableForLinting(capabilities: capabilities)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status: a filled check when the rule is on in this configuration, an
            // empty circle when it's off, whether it's a default or an opt-in rule.
            // The shape carries the state (colour only reinforces it), and VoiceOver
            // reads it from the label.
            Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(rule.isEnabled ? Color.green : Color.secondary)
                .help(rule.isEnabled ? "Enabled in this configuration" : "Disabled in this configuration")
                .accessibilityLabel(rule.isEnabled ? "Enabled" : "Disabled")
                .accessibilityIdentifier("RuleStatusSymbol")

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

                // Category badge and opt-in tag. On/off is the status symbol's job;
                // this row says what kind of rule it is. The tag stays neutral so
                // orange keeps meaning "warning" across the app.
                HStack(spacing: 8) {
                    CategoryBadge(
                        category: rule.category,
                        color: RuleCategoryColors.color(for: rule.category)
                    )

                    if rule.isOptIn {
                        Label("Opt-In", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("SwiftLint runs this rule only when a configuration enables it")
                    }

                    if isUnavailable {
                        Label("Not checked in this app", systemImage: "nosign")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("This rule depends on SourceKit, so it isn't checked in this "
                                + "app. You can still add it to your configuration.")
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
