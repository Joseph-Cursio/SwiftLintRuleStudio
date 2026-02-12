//
//  ConfigDiffPreviewView.swift
//  SwiftLintRuleStudio
//
//  View for previewing configuration changes before saving
//

import SwiftUI

struct ConfigDiffPreviewView: View {
    let diff: YAMLConfigurationEngine.ConfigDiff
    let ruleName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State var selectedView: DiffViewMode = .summary
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
        selectedView: DiffViewMode = .summary
    ) {
        self.diff = diff
        self.ruleName = ruleName
        self.onSave = onSave
        self.onCancel = onCancel
        self._selectedView = State(initialValue: selectedView)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview Configuration Changes")
                        .font(.headline)
                    
                    Text("Review the changes that will be made to your .swiftlint.yml file")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Content
                if selectedView == .summary {
                    summaryView
                } else {
                    fullDiffView
                }
                
                Divider()
                
                // Actions
                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("Save Changes") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding()
            }
            .frame(width: 700, height: 500)
            .toolbar {
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
                            .foregroundColor(.secondary)
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
                    .foregroundColor(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            ForEach(rules, id: \.self) { ruleId in
                HStack {
                    Text("•")
                        .foregroundColor(color)
                    Text(ruleId)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var fullDiffView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Before
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(diff.before.isEmpty ? "(empty configuration)" : diff.before)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
                
                Divider()
                
                // After
                VStack(alignment: .leading, spacing: 8) {
                    Text("After")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Text(diff.after.isEmpty ? "(empty configuration)" : diff.after)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
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
