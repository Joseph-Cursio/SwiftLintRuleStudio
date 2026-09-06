//
//  RuleAuditRow.swift
//  SwiftLintRuleStudio
//
//  Individual rule row for the Rule Audit view with proportional bar,
//  affected files, auto-fix indicator, and expandable detail panel
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Column subviews

/// The category chip.
///
/// `RuleAuditRow` re-renders whenever any of its nine inputs changes — the expansion flag, the
/// selection flag, the file totals, three callbacks. These four columns depend on the entry alone,
/// so as inlined properties they were redrawn every time a neighbouring row was expanded or
/// selected. Each now takes only the values it draws, all of them value types, so SwiftUI compares
/// them equal and skips.
private struct AuditCategoryBadge: View {
    let category: RuleCategory

    /// The shared mapping, not a local one.
    ///
    /// This was a private switch giving `style` purple, `lint` blue, `metrics` green and
    /// `idiomatic` teal — while `RuleCategoryColors`, used by the rule list and the rule detail
    /// header, gives them blue, red, purple and green. Four of five categories disagreed, so the
    /// same rule wore a different badge colour depending on which screen you were looking at.
    private var categoryColor: Color { RuleCategoryColors.color(for: category) }

    var body: some View {
        Text(category.displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
            .frame(width: AuditColumnWidths.category)
    }
}

/// Whether the rule can autocorrect.
private struct AutoFixIndicator: View {
    let supportsAutocorrection: Bool

    var body: some View {
        Group {
            if supportsAutocorrection {
                Text("Yes")
                    .foregroundStyle(.green)
            } else {
                Text("No")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(width: AuditColumnWidths.autoFix)
    }
}

/// Affected files, as a count or a fraction of the workspace.
private struct AffectedFilesDisplay: View {
    let isCurrentlyEnabled: Bool
    let affectedFileCount: Int
    let totalSwiftFiles: Int

    var body: some View {
        Group {
            if isCurrentlyEnabled {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if totalSwiftFiles > 0 {
                Text("\(affectedFileCount) / \(totalSwiftFiles)")
            } else {
                Text("\(affectedFileCount)")
            }
        }
        .font(.caption)
        .frame(width: AuditColumnWidths.affectedFiles)
    }
}

/// Enabled or disabled, as a chip.
private struct AuditStatusBadge: View {
    let isCurrentlyEnabled: Bool

    var body: some View {
        Group {
            if isCurrentlyEnabled {
                Text("enabled")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("disabled")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .font(.caption2)
        .frame(width: AuditColumnWidths.status)
    }
}

struct RuleAuditRow: View {
    let entry: RuleAuditEntry
    let isExpanded: Bool
    let isSelected: Bool
    let totalSwiftFiles: Int
    let maxViolationCount: Int
    let onToggleExpand: () -> Void
    let onToggleSelect: () -> Void
    let onEnable: () -> Void
    @Environment(\.appCapabilities) private var capabilities: Set<AppCapability>

    private var isExpandable: Bool {
        !entry.isCurrentlyEnabled && entry.violationCount > 0
    }

    private var isUnavailable: Bool {
        entry.rule.isUnavailableForLinting(capabilities: capabilities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
                .onTapGesture {
                    if isExpandable {
                        onToggleExpand()
                    }
                }
                // Collapse the ~9 columns into one VoiceOver element with a composed
                // summary; expose the interactive columns as named actions instead of
                // separate stops. `.isButton` only when the row can be expanded.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityHint(isExpandable ? "Double tap to expand the file breakdown" : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityActions {
                    if isExpandable {
                        Button(isExpanded ? "Collapse details" : "Expand details", action: onToggleExpand)
                    }
                    if !entry.isCurrentlyEnabled {
                        Button(isSelected ? "Deselect rule" : "Select rule", action: onToggleSelect)
                        Button("Enable rule", action: onEnable)
                    }
                }
            if isExpanded && isExpandable {
                expandedDetail
            }
        }
        .opacity(entry.isCurrentlyEnabled ? 0.5 : 1.0)
    }

    private var rowAccessibilityLabel: String {
        var parts = [entry.rule.id, entry.rule.description]
        if entry.isCurrentlyEnabled {
            parts.append("already enabled")
        } else {
            parts.append("\(entry.violationCount) violations")
            parts.append(entry.effortCategory.label)
        }
        if isUnavailable {
            parts.append("not available in this edition")
        }
        return parts.joined(separator: ", ")
    }

    private var mainRow: some View {
        HStack(spacing: AuditColumnWidths.spacing) {
            // Checkbox (disabled for already-enabled rules)
            if !entry.isCurrentlyEnabled {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .accessibilityLabel(isSelected ? "Deselect rule" : "Select rule")
                }
                .buttonStyle(.plain)
                .frame(width: AuditColumnWidths.checkbox)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: AuditColumnWidths.checkbox)
                    .accessibilityLabel("Already enabled")
            }

            // Expand/collapse disclosure
            if isExpandable {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
                }
                .buttonStyle(.plain)
                .frame(width: AuditColumnWidths.disclosure)
            } else {
                Spacer().frame(width: AuditColumnWidths.disclosure)
            }

            // Rule name + description (flexible column)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.rule.id)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isUnavailable {
                        Image(systemName: "nosign")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Relies on SourceKit — not evaluated in this edition. "
                                + "Still writable to your configuration.")
                            .accessibilityLabel("Not available in this edition")
                    }
                }
                Text(entry.rule.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Category badge
            AuditCategoryBadge(category: entry.category)

            // Violations + proportional bar
            violationDisplay

            // Auto-fixable
            AutoFixIndicator(supportsAutocorrection: entry.rule.supportsAutocorrection)

            // Affected files
            AffectedFilesDisplay(
                isCurrentlyEnabled: entry.isCurrentlyEnabled,
                affectedFileCount: entry.affectedFileCount,
                totalSwiftFiles: totalSwiftFiles
            )

            // Status
            AuditStatusBadge(isCurrentlyEnabled: entry.isCurrentlyEnabled)

            // Action
            actionColumn
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Kept inline deliberately.
    ///
    /// Extracting it would hand a child `onEnable`, a closure the row is given rather than one it
    /// makes. Its call site decides whether it captures, and a child holding a capturing closure
    /// was measured to re-render exactly as often as the property it replaced — so there would be
    /// no update to skip. The rule agrees now — its capture gate saw a closure a property creates
    /// and not one it forwards, and this property was one of the thirteen that closing the gap
    /// silenced.
    private var actionColumn: some View {
        Group {
            if !entry.isCurrentlyEnabled {
                Button("Enable", action: onEnable)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(width: AuditColumnWidths.action)
    }

    private var violationDisplay: some View {
        HStack(spacing: 6) {
            Text("\(entry.violationCount)")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(entry.effortCategory.color)
                .frame(width: 36, alignment: .trailing)

            // Proportional bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 6)

                    if entry.violationCount > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.effortCategory.color)
                            .frame(
                                width: barWidth(in: geometry.size.width),
                                height: 6
                            )
                    }
                }
                .frame(height: geometry.size.height)
            }
            .frame(width: 60, height: 16)
            .accessibilityHidden(true)
        }
        .frame(width: AuditColumnWidths.violations)
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        guard maxViolationCount > 0 else { return 0 }
        let proportion = CGFloat(entry.violationCount) / CGFloat(maxViolationCount)
        return max(proportion * totalWidth, 3)
    }
}
