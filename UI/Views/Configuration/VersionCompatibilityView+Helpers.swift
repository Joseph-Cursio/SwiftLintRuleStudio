import SwiftUI

extension VersionCompatibilityView {
    func removedRulesSection(_ rules: [RemovedRuleInfo]) -> some View {
        issueSection(
            title: "Removed Rules",
            subtitle: "These rules no longer exist and must be removed",
            color: .red,
            icon: "xmark.circle.fill"
        ) {
            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.ruleId)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(rule.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Removed in \(rule.removedInVersion)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    func deprecatedRulesSection(_ rules: [DeprecatedRuleInfo]) -> some View {
        issueSection(
            title: "Deprecated Rules",
            subtitle: "These rules still work but should be migrated",
            color: .orange,
            icon: "exclamationmark.triangle.fill"
        ) {
            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.ruleId)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(rule.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let replacement = rule.replacement {
                        Text("Use: \(replacement)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    func renamedRulesSection(_ rules: [RenamedRuleInfo]) -> some View {
        issueSection(
            title: "Renamed Rules",
            subtitle: "These rules have been renamed",
            color: .yellow,
            icon: "arrow.right.circle.fill"
        ) {
            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(rule.oldRuleId)
                                .font(.system(.body, design: .monospaced))
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .accessibilityHidden(true)
                            Text(rule.newRuleId)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    Button("Fix") {
                        viewModel.applyRenaming(rule)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Fix All Renames") {
                viewModel.applyAllFixes()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    func newRulesAvailableSection(_ ruleIds: [String]) -> some View {
        issueSection(
            title: "New Rules Available",
            subtitle: "Rules added in recent SwiftLint versions that you could enable",
            color: .green,
            icon: "plus.circle.fill"
        ) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(ruleIds, id: \.self) { ruleId in
                    Text(ruleId)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
        }
    }

    func issueSection<Content: View>(
        title: String,
        subtitle: String,
        color: Color,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
