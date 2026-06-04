//
//  ResolvedConfigInspectorView.swift
//  SwiftLintRuleStudio
//
//  The resolved-config inspector for the folder selected in the Config Map:
//  layer chain, per-rule state with "set by" attribution, and only_rules /
//  excluded / inherits notices.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ResolvedConfigInspectorView: View {
    let display: ResolvedConfigDisplay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                notices
                Divider()
                ruleTable
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.targetLabel)
                .font(.title2.weight(.semibold))
            Text("Layer chain: \(display.layerChainLabels.joined(separator: " ▸ "))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ConfigMapLayerChain")
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let inherits = display.inheritsNotice {
            noticeRow(inherits, systemImage: "info.circle", tint: .blue)
        }
        if let only = display.onlyRulesNotice {
            noticeRow(only, systemImage: "lock.fill", tint: .orange)
        }
        if let excluded = display.excludedNotice {
            noticeRow(excluded, systemImage: "minus.circle", tint: .secondary)
        }
    }

    @ViewBuilder
    private var ruleTable: some View {
        if display.ruleRows.isEmpty {
            Text("No rule changes from the SwiftLint defaults in this folder.")
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    columnTitle("Rule")
                    columnTitle("State")
                    columnTitle("Set by")
                }
                ForEach(display.ruleRows) { row in
                    GridRow {
                        Text(row.ruleIdentifier)
                            .font(.body.monospaced())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.state)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(row.setBy)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func noticeRow(_ text: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .font(.callout)
    }
}
