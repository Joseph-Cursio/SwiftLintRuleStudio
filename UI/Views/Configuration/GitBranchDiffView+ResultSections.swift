//
//  GitBranchDiffView+ResultSections.swift
//  SwiftLintRuleStudio
//
//  The sections that list one kind of difference in a branch comparison
//

import SwiftLintRuleStudioCore
import SwiftUI

extension GitBranchDiffView {
    func modifiedRulesSection(_ diffs: [RuleComparisonDiff]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Different Settings")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            ForEach(diffs) { diff in
                VStack(alignment: .leading, spacing: 4) {
                    Text(diff.ruleId)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    ForEach(diff.differences, id: \.self) { detail in
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    func lineSection(title: String, lines: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .padding(.leading, 24)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    func diffSection(title: String, rules: [String], color: Color, icon: String) -> some View {
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
                Text(ruleId)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 24)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}
