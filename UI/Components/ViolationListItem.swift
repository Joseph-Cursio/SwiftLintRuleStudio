//
//  ViolationListItem.swift
//  SwiftLintRuleStudio
//
//  Component for displaying a violation in a list
//

import SwiftUI

struct ViolationListItem: View {
    let violation: Violation
    
    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Rule ID and severity
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(violation.ruleID)
                        .font(.headline)
                        .lineLimit(1)
                    
                    SeverityBadge(severity: violation.severity)
                    
                    if violation.suppressed {
                        Label("Suppressed", systemImage: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Message
                Text(violation.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // File and line
                HStack(spacing: 8) {
                    Label(violation.filePath, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Label("Line \(violation.line)", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var severityColor: Color {
        switch violation.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity
    
    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2))
            .foregroundColor(severityColor)
            .cornerRadius(4)
    }
    
    private var severityColor: Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        }
    }
}



