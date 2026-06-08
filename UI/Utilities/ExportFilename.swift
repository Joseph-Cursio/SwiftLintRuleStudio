//
//  ExportFilename.swift
//  SwiftLintRuleStudio
//
//  Shared helpers for building export filenames.
//

import Foundation

/// Helpers for constructing export filenames consistently across export paths.
enum ExportFilename {
    /// Formats a timestamp suitable for an export filename (`yyyyMMdd_HHmmss`).
    /// - Parameter date: The date to format. Defaults to now.
    /// - Returns: A filename-safe timestamp string.
    static func timestamp(from date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
