//
//  ConfigTreeRowView.swift
//  SwiftLintRuleStudio
//
//  One row in the sparse Config Tree: a config-bearing folder, indented by its
//  position in the config tree, with a "what it changes" badge.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ConfigTreeRowView: View {
    let row: ConfigTreeRow

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: row.hasParseError ? "exclamationmark.octagon.fill" : "doc.text")
                .foregroundStyle(row.hasParseError ? Color.red : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .fontWeight(row.isRoot ? .semibold : .regular)
                if let badge = row.badge {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let replaced = row.replaces {
                    Text("replaces \(replaced)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("SwiftLint applies only the nearest nested config: files here get none of \(replaced)'s.")
                }
                if !row.pullsIn.isEmpty {
                    Text(pullsInText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("The root config pulls these in with parent_config or child_config. "
                            + "Their settings are part of the root's, in every folder.")
                }
            }
            Spacer(minLength: 0)
            if row.hasIneffectiveExclusions {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Nested excluded/included is ignored by SwiftLint — only the root config's applies.")
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, CGFloat(row.indentLevel) * 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var pullsInText: String {
        "pulls in \(row.pullsIn.joined(separator: ", "))"
    }

    private var accessibilityText: String {
        var parts = [row.displayName]
        if let badge = row.badge { parts.append(badge) }
        if let replaced = row.replaces { parts.append("replaces \(replaced)") }
        if !row.pullsIn.isEmpty { parts.append(pullsInText) }
        if row.hasIneffectiveExclusions { parts.append("ineffective exclusions") }
        return parts.joined(separator: ", ")
    }
}
