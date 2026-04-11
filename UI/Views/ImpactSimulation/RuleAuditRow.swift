//
//  RuleAuditRow.swift
//  SwiftLintRuleStudio
//
//  Individual rule row for the Rule Audit view with proportional bar,
//  affected files, auto-fix indicator, and expandable detail panel
//

import SwiftUI
import SwiftLintRuleStudioCore

struct RuleAuditRow: View {
    let entry: RuleAuditEntry
    let isExpanded: Bool
    let isSelected: Bool
    let totalSwiftFiles: Int
    let maxViolationCount: Int
    let onToggleExpand: () -> Void
    let onToggleSelect: () -> Void
    let onEnable: () -> Void

    private var isExpandable: Bool {
        !entry.isCurrentlyEnabled && entry.violationCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
                .onTapGesture {
                    if isExpandable {
                        onToggleExpand()
                    }
                }
            if isExpanded && isExpandable {
                expandedDetail
            }
        }
        .opacity(entry.isCurrentlyEnabled ? 0.5 : 1.0)
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
                Text(entry.rule.id)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(entry.rule.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Category badge
            categoryBadge

            // Violations + proportional bar
            violationDisplay

            // Auto-fixable
            autoFixIndicator

            // Affected files
            affectedFilesDisplay

            // Status
            statusBadge

            // Action
            actionColumn
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

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

    private var categoryBadge: some View {
        Text(entry.rule.category.displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
            .frame(width: AuditColumnWidths.category)
    }

    private var categoryColor: Color {
        switch entry.rule.category {
        case .style: .purple
        case .lint: .blue
        case .metrics: .green
        case .performance: .orange
        case .idiomatic: .teal
        }
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
        }
        .frame(width: AuditColumnWidths.violations)
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        guard maxViolationCount > 0 else { return 0 }
        let proportion = CGFloat(entry.violationCount) / CGFloat(maxViolationCount)
        return max(proportion * totalWidth, 3)
    }

    private var autoFixIndicator: some View {
        Group {
            if entry.rule.supportsAutocorrection {
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

    private var affectedFilesDisplay: some View {
        Group {
            if entry.isCurrentlyEnabled {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if totalSwiftFiles > 0 {
                Text("\(entry.affectedFileCount) / \(totalSwiftFiles)")
            } else {
                Text("\(entry.affectedFileCount)")
            }
        }
        .font(.caption)
        .frame(width: AuditColumnWidths.affectedFiles)
    }

    private var statusBadge: some View {
        Group {
            if entry.isCurrentlyEnabled {
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

// MARK: - Expanded Detail

extension RuleAuditRow {
    var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                fileBreakdown
                Divider()
                exampleViolation
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.leading, 46)
        .padding(.vertical, 4)
    }

    private var fileBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File Breakdown")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            let topFiles = Array(entry.violationsByFile.prefix(5))
            ForEach(topFiles, id: \.file) { item in
                HStack(spacing: 8) {
                    Text(item.file)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 160, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(NSColor.separatorColor))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(entry.effortCategory.color)
                                .frame(
                                    width: fileBarWidth(
                                        count: item.count,
                                        in: geometry.size.width
                                    ),
                                    height: 4
                                )
                        }
                        .frame(height: geometry.size.height)
                    }
                    .frame(width: 80, height: 10)

                    Text("\(item.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            let remaining = entry.violationsByFile.count - topFiles.count
            if remaining > 0 {
                Text("+ \(remaining) more files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 300, alignment: .leading)
    }

    private func fileBarWidth(count: Int, in totalWidth: CGFloat) -> CGFloat {
        guard let maxCount = entry.violationsByFile.first?.count, maxCount > 0 else { return 0 }
        let proportion = CGFloat(count) / CGFloat(maxCount)
        return max(proportion * totalWidth, 2)
    }

    private var exampleViolation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Example Violation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let firstViolation = entry.violations.first {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: firstViolation.severity == .error
                              ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(firstViolation.severity == .error ? .red : .orange)
                            .accessibilityLabel(
                                firstViolation.severity == .error ? "Error" : "Warning"
                            )

                        Text(firstViolation.filePath)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text("Line \(firstViolation.line)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(firstViolation.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if entry.rule.supportsAutocorrection {
                    Label(
                        "All \(entry.violationCount) violations are auto-fixable",
                        systemImage: "wrench.and.screwdriver.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.top, 2)
                }
            } else {
                Text("No violation details available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .frame(minWidth: 250, alignment: .leading)
    }
}
