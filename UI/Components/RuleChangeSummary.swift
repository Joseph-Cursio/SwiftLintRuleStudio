//
//  RuleChangeSummary.swift
//  SwiftLintRuleStudio
//
//  Summary of added/removed/modified rule counts from a config diff.
//

import SwiftLintRuleStudioCore
import SwiftUI

/// Summarizes the added/removed/modified rule counts of a configuration diff.
/// Shared by the import preview and migration preview so both render the
/// change summary identically.
struct RuleChangeSummary: View {
    let diff: YAMLConfigurationEngine.ConfigDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !diff.addedRules.isEmpty {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("\(diff.addedRules.count) rule(s) to add")
                }
            }
            if !diff.removedRules.isEmpty {
                HStack {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("\(diff.removedRules.count) rule(s) to remove")
                }
            }
            if !diff.modifiedRules.isEmpty {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("\(diff.modifiedRules.count) rule(s) to modify")
                }
            }
        }
    }
}
