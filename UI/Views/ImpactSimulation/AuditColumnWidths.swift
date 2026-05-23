//
//  AuditColumnWidths.swift
//  SwiftLintRuleStudio
//

import SwiftUI

/// Fixed column widths shared between header and data rows
enum AuditColumnWidths {
    static let checkbox: CGFloat = 20
    static let disclosure: CGFloat = 14
    static let category: CGFloat = 85
    static let violations: CGFloat = 110
    static let autoFix: CGFloat = 65
    static let affectedFiles: CGFloat = 75
    static let status: CGFloat = 70
    static let action: CGFloat = 55
    static let spacing: CGFloat = 12
    /// Total fixed width consumed by non-flexible columns
    static let leadingFixed: CGFloat = checkbox + spacing + disclosure + spacing
}
