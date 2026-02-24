import SwiftUI

extension RuleDetailView {
    var configurationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                // Toggle at the top with full width
                HStack {
                    Toggle("Enable this rule", isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.updateEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("RuleDetailEnableToggle")
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                if viewModel.isEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Severity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Severity", selection: Binding(
                            get: { viewModel.severity ?? .warning },
                            set: { viewModel.updateSeverity($0) }
                        )) {
                            ForEach(Severity.allCases) { severity in
                                Text(severity.displayName).tag(severity)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }

                    if let parameters = rule.parameters, !parameters.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Parameters")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            RuleParameterEditor(
                                parameters: parameters,
                                values: $viewModel.parameterValues
                            )
                        }
                    }
                }

                if viewModel.pendingChanges != nil {
                    Divider()

                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("You have unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Simulate button
                if dependencies.workspaceManager.currentWorkspace != nil {
                    Divider()

                    Button {
                        simulateRule()
                    } label: {
                        HStack {
                            if isSimulating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "chart.bar.fill")
                                    .accessibilityHidden(true)
                            }
                            Text("Simulate Impact")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSimulating)
                    .accessibilityIdentifier("RuleDetailSimulateButton")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
    }

    var examplesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Examples")
                .font(.headline)

            if !rule.triggeringExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Triggering Examples", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    ForEach(Array(rule.triggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: true)
                    }
                }
            }

            if !rule.nonTriggeringExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Non-Triggering Examples", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    ForEach(Array(rule.nonTriggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: false)
                    }
                }
            }

            if rule.triggeringExamples.isEmpty && rule.nonTriggeringExamples.isEmpty {
                Text("No examples available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    var violationsCountView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Violations")
                .font(.headline)

            if isLoadingViolationCount {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Text("\(violationCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(violationCount > 0 ? .orange : .green)

                    Text(violationCount == 1 ? "violation" : "violations")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if violationCount > 0 {
                        Text("in current workspace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var relatedRulesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Rules")
                .font(.headline)

            let related = relatedRules
            if related.isEmpty {
                Text("No related rules found")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(related.prefix(5), id: \.id) { relatedRule in
                        Button {
                            // Navigate to related rule - would need navigation handling
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Text(relatedRule.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    if related.count > 5 {
                        Text("+ \(related.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }
        }
    }

    var swiftEvolutionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swift Evolution")
                .font(.headline)

            let links = extractSwiftEvolutionLinks(from: rule.markdownDocumentation ?? "")
            if links.isEmpty {
                Text("No Swift Evolution proposals linked")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(links, id: \.self) { link in
                        Link(destination: link) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(link.absoluteString)
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}
