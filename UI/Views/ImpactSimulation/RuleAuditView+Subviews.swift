//
//  RuleAuditView+Subviews.swift
//  SwiftLintRuleStudio
//
//  Subviews for the Rule Audit view: summary cards, rule rows, expanded detail, status bar
//

import SwiftUI
import SwiftLintRuleStudioCore

// MARK: - Summary Cards

extension RuleAuditView {
    var summaryCardsView: some View {
        let summary = AuditSummary(
            entries: auditEntries,
            totalSwiftFiles: totalSwiftFiles,
            auditDuration: auditDuration
        )

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SummaryCard(
                    title: "SAFE TO ENABLE",
                    count: summary.safeCount,
                    subtitle: "0 violations",
                    color: .green
                )

                SummaryCard(
                    title: "LOW EFFORT",
                    count: summary.lowCount,
                    subtitle: "1-5 violations",
                    color: .yellow
                )

                SummaryCard(
                    title: "MODERATE EFFORT",
                    count: summary.moderateCount,
                    subtitle: "6-25 violations",
                    color: .orange
                )

                SummaryCard(
                    title: "HIGH EFFORT",
                    count: summary.highCount,
                    subtitle: "26+ violations",
                    color: .red
                )

                enableAllSafeButton(safeCount: summary.safeCount)
            }
            .padding()
        }
    }

    private func enableAllSafeButton(safeCount: Int) -> some View {
        Button {
            selectAndEnableAllSafeRules()
        } label: {
            VStack(spacing: 6) {
                Text("Enable All Safe Rules")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("\(safeCount) rules")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("0 new violations")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 160, height: 70)
        }
        .buttonStyle(.borderedProminent)
        .disabled(safeCount == 0 || isEnabling)
        .accessibilityIdentifier("EnableAllSafeRulesButton")
    }
}

// MARK: - Rule List

extension RuleAuditView {
    var ruleListView: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider()
            List {
                ForEach(auditEntries) { entry in
                    RuleAuditRow(
                        entry: entry,
                        isExpanded: expandedRuleId == entry.id,
                        isSelected: selectedRules.contains(entry.id),
                        totalSwiftFiles: totalSwiftFiles,
                        maxViolationCount: maxViolationCount,
                        onToggleExpand: { toggleExpanded(entry.id) },
                        onToggleSelect: { toggleSelection(for: entry.id) },
                        onEnable: { enableSingleRule(entry.rule) }
                    )
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var columnHeader: some View {
        HStack(spacing: AuditColumnWidths.spacing) {
            // Checkbox placeholder
            Spacer().frame(width: AuditColumnWidths.checkbox)
            // Disclosure placeholder
            Spacer().frame(width: AuditColumnWidths.disclosure)
            // Rule name (flexible)
            Text("RULE")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CATEGORY")
                .frame(width: AuditColumnWidths.category)
            Text("VIOLATIONS")
                .frame(width: AuditColumnWidths.violations)
            Text("AUTO-FIX")
                .frame(width: AuditColumnWidths.autoFix)
            Text("FILES")
                .frame(width: AuditColumnWidths.affectedFiles)
            Text("STATUS")
                .frame(width: AuditColumnWidths.status)
            Text("ACTION")
                .frame(width: AuditColumnWidths.action)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var maxViolationCount: Int {
        auditEntries.map(\.violationCount).max() ?? 1
    }

    func toggleExpanded(_ ruleId: String) {
        if expandedRuleId == ruleId {
            expandedRuleId = nil
        } else {
            expandedRuleId = ruleId
        }
    }

    func toggleSelection(for ruleId: String) {
        if selectedRules.contains(ruleId) {
            selectedRules.remove(ruleId)
        } else {
            selectedRules.insert(ruleId)
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let title: String
    let count: Int
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(color)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 180, height: 70, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Status Bar

extension RuleAuditView {
    var statusBar: some View {
        HStack(spacing: 16) {
            let summary = AuditSummary(
                entries: auditEntries,
                totalSwiftFiles: totalSwiftFiles,
                auditDuration: auditDuration
            )

            Text("Audit completed in \(String(format: "%.1fs", summary.auditDuration))")
                .foregroundStyle(.secondary)

            Divider().frame(height: 12)

            if totalSwiftFiles > 0 {
                Text("\(summary.totalRulesTested) rules tested against \(totalSwiftFiles) Swift files")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(summary.totalRulesTested) rules tested")
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 12)

            Text("\(summary.safeCount) safe rules ready to enable")
                .foregroundStyle(.green)

            Spacer()

            if !selectedRules.isEmpty {
                Text("\(selectedRules.count) rules selected")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
