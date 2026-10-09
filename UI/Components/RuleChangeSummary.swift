//
//  RuleChangeSummary.swift
//  SwiftLintRuleStudio
//
//  Summary of added/removed/modified rule counts from a config diff.
//

import SwiftLintRuleStudioCore
import SwiftUI

/// Summarizes what a configuration diff changes, as counts. Shared by the import preview and
/// migration preview so both render the change summary identically.
struct RuleChangeSummary: View {
    let diff: YAMLConfigurationEngine.ConfigDiff

    @Environment(\.ruleRegistry) private var ruleRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let changes = diff.knowing(ruleRegistry.rules).changes {
                lines(for: changes)
            } else {
                ruleKeyLines
            }
        }
    }

    /// Counts of what SwiftLint will check differently, including changes made through rule
    /// lists such as `opt_in_rules`.
    @ViewBuilder
    private func lines(for changes: ConfigChangeSummary) -> some View {
        if changes.isEmpty {
            line("SwiftLint checks the same things", icon: "equal.circle.fill", color: .secondary)
        }
        if !changes.turnedOn.isEmpty {
            line("\(changes.turnedOn.count) rule(s) turned on", icon: "plus.circle.fill", color: .green)
        }
        if !changes.turnedOff.isEmpty {
            line("\(changes.turnedOff.count) rule(s) turned off", icon: "minus.circle.fill", color: .red)
        }
        if !changes.settingsChanged.isEmpty {
            line(
                "\(changes.settingsChanged.count) rule(s) with changed settings",
                icon: "pencil.circle.fill",
                color: .orange
            )
        }
        if !changes.pathChanges.isEmpty {
            line("Paths changed", icon: "folder.fill", color: .secondary)
        }
        if !changes.otherChanges.isEmpty {
            line("\(changes.otherChanges.count) other setting(s) changed", icon: "gearshape.fill", color: .secondary)
        }
    }

    /// Rule keys added, removed or changed in the per-rule settings blocks, for a diff that
    /// carries nothing more.
    @ViewBuilder
    private var ruleKeyLines: some View {
        if !diff.addedRules.isEmpty {
            line("\(diff.addedRules.count) rule(s) to add", icon: "plus.circle.fill", color: .green)
        }
        if !diff.removedRules.isEmpty {
            line("\(diff.removedRules.count) rule(s) to remove", icon: "minus.circle.fill", color: .red)
        }
        if !diff.modifiedRules.isEmpty {
            line("\(diff.modifiedRules.count) rule(s) to modify", icon: "pencil.circle.fill", color: .orange)
        }
    }

    private func line(_ text: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}
