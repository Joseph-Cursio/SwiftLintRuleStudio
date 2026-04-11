//
//  ConfigDiffPreviewView.swift
//  SwiftLintRuleStudio
//
//  View for previewing configuration changes before saving
//

import SwiftUI
import SwiftLintRuleStudioCore

struct ConfigDiffPreviewView: View {
    let diff: YAMLConfigurationEngine.ConfigDiff
    let ruleName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var isInline: Bool = false

    @State private var selectedView: DiffViewMode = .summary
    @State private var showCopiedFeedback = false

    enum DiffViewMode {
        case summary
        case full
    }

    init(
        diff: YAMLConfigurationEngine.ConfigDiff,
        ruleName: String,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        selectedView: DiffViewMode = .summary,
        isInline: Bool = false
    ) {
        self.diff = diff
        self.ruleName = ruleName
        self.onSave = onSave
        self.onCancel = onCancel
        self.isInline = isInline
        self._selectedView = State(initialValue: selectedView)
    }

    var body: some View {
        if isInline {
            inlineBody
        } else {
            modalBody
        }
    }

    private var modalBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                diffHeader
                Divider()
                diffContent
                Divider()
                diffActions
            }
            .frame(width: 700, height: 500)
            .toolbar { diffToolbar }
        }
    }

    private var inlineBody: some View {
        VStack(spacing: 0) {
            inlineToolbar
            Divider()
            diffContent
            Divider()
            diffActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inlineToolbar: some View {
        HStack {
            Picker("View", selection: $selectedView) {
                Text("Summary").tag(DiffViewMode.summary)
                Text("Full Diff").tag(DiffViewMode.full)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            Button {
                copyForPR()
            } label: {
                Label(
                    showCopiedFeedback ? "Copied!" : "Copy for PR",
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(showCopiedFeedback)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var diffHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview Configuration Changes")
                .font(.headline)
            Text("Review the changes that will be made to your .swiftlint.yml file")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var diffContent: some View {
        if selectedView == .summary {
            summaryView
        } else {
            fullDiffView
        }
    }

    private var diffActions: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.escape)
            Spacer()
            Button("Save Changes") { onSave() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var diffToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $selectedView) {
                Text("Summary").tag(DiffViewMode.summary)
                Text("Full Diff").tag(DiffViewMode.full)
            }
            .pickerStyle(.segmented)

            Button {
                copyForPR()
            } label: {
                Label(
                    showCopiedFeedback ? "Copied!" : "Copy for PR",
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(showCopiedFeedback)
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Changes Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Changes Summary")
                        .font(.headline)

                    if !diff.addedRules.isEmpty {
                        changeSection(
                            title: "Rules to be Added",
                            rules: diff.addedRules,
                            color: .green,
                            icon: "plus.circle.fill"
                        )
                    }

                    if !diff.removedRules.isEmpty {
                        changeSection(
                            title: "Rules to be Removed",
                            rules: diff.removedRules,
                            color: .red,
                            icon: "minus.circle.fill"
                        )
                    }

                    if !diff.modifiedRules.isEmpty {
                        changeSection(
                            title: "Rules to be Modified",
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
                .padding()
            }
            .padding()
        }
    }

    private func changeSection(title: String, rules: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

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
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var fullDiffView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Before
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text(diff.before.isEmpty ? "(empty configuration)" : diff.before)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(.rect(cornerRadius: 8))
                }

                Divider()

                // After
                VStack(alignment: .leading, spacing: 8) {
                    Text("After")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text(diff.after.isEmpty ? "(empty configuration)" : diff.after)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            .padding()
        }
    }

    private func copyForPR() {
        let generator = PRCommentGenerator()
        let markdown = generator.generateMarkdown(from: diff)
        generator.copyToClipboard(markdown)

        showCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedFeedback = false
        }
    }
}

#Preview {
    let diff = YAMLConfigurationEngine.ConfigDiff(
        addedRules: ["new_rule"],
        removedRules: [],
        modifiedRules: ["force_cast"],
        before: "rules:\n  force_cast: error",
        after: "rules:\n  force_cast: warning\n  new_rule: error"
    )

    return ConfigDiffPreviewView(
        diff: diff,
        ruleName: "Test Rule",
        onSave: {},
        onCancel: {}
    )
}
