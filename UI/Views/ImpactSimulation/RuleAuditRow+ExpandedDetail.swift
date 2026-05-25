//
//  RuleAuditRow+ExpandedDetail.swift
//  SwiftLintRuleStudio
//
//  The expandable per-rule detail panel rendered below a RuleAuditRow
//  when the user taps to expand: file breakdown on the left and an
//  example violation on the right.
//

import SwiftLintRuleStudioCore
import SwiftUI

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
