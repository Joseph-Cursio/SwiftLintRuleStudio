//
//  ConfigDiffSummaryView.swift
//  SwiftLintRuleStudio
//
//  The Summary tab of a configuration diff: what SwiftLint will check differently.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ConfigDiffSummaryView: View {
    let diff: YAMLConfigurationEngine.ConfigDiff
    /// Section titles for a diff that only lists changed per-rule settings blocks.
    let addedLabel: String
    let removedLabel: String
    let modifiedLabel: String

    @Environment(\.ruleRegistry) private var ruleRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Changes Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Changes Summary")
                        .font(.headline)

                    // The catalog says for certain which rules are opt-in.
                    if let changes = diff.knowing(ruleRegistry.rules).changes {
                        changeSummary(changes)
                    } else {
                        ruleKeySummary
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    /// What SwiftLint will check differently, for a diff built from two parsed configurations.
    @ViewBuilder
    private func changeSummary(_ changes: ConfigChangeSummary) -> some View {
        if changes.isEmpty {
            Text(
                diff.before == diff.after
                    ? "The two versions are identical."
                    : "The text differs, but SwiftLint checks the same things."
            )
            .foregroundStyle(.secondary)
            .italic()
        }
        if !changes.turnedOn.isEmpty {
            changeSection(title: "Rules turned on", rules: changes.turnedOn, color: .green, icon: "plus.circle.fill")
        }
        if !changes.turnedOff.isEmpty {
            changeSection(title: "Rules turned off", rules: changes.turnedOff, color: .red, icon: "minus.circle.fill")
        }
        if !changes.settingsChanged.isEmpty {
            settingsSection(changes.settingsChanged)
        }
        if !changes.pathChanges.isEmpty {
            noteSection(title: "Paths", lines: changes.pathChanges, icon: "folder.fill")
        }
        if !changes.otherChanges.isEmpty {
            noteSection(title: "Other changes", lines: changes.otherChanges, icon: "gearshape.fill")
        }
    }

    /// Rule keys added, removed or changed in the per-rule settings blocks, for a diff that
    /// carries nothing more.
    @ViewBuilder
    private var ruleKeySummary: some View {
        if !diff.addedRules.isEmpty {
            changeSection(
                title: addedLabel,
                rules: diff.addedRules,
                color: .green,
                icon: "plus.circle.fill"
            )
        }

        if !diff.removedRules.isEmpty {
            changeSection(
                title: removedLabel,
                rules: diff.removedRules,
                color: .red,
                icon: "minus.circle.fill"
            )
        }

        if !diff.modifiedRules.isEmpty {
            changeSection(
                title: modifiedLabel,
                rules: diff.modifiedRules,
                color: .orange,
                icon: "pencil.circle.fill"
            )
        }

        if diff.addedRules.isEmpty && diff.removedRules.isEmpty && diff.modifiedRules.isEmpty {
            Text("No changes detected")
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    private func settingsSection(_ changes: [ConfigChangeSummary.SettingChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Settings changed", color: .orange, icon: "pencil.circle.fill")
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.ruleId)
                        .font(.system(.body, design: .monospaced))
                    ForEach(change.details, id: \.self) { detail in
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func noteSection(title: String, lines: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, color: .secondary, icon: icon)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .padding(.leading, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func sectionTitle(_ title: String, color: Color, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    private func changeSection(title: String, rules: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, color: color, icon: icon)

            ForEach(rules, id: \.self) { ruleId in
                HStack {
                    Text("•")
                        .foregroundStyle(color)
                    Text(ruleId)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}
