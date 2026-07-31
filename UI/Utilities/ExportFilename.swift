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
        // Pin the locale and calendar: with a fixed dateFormat, the ambient
        // locale still decides the era, so a Japanese-calendar user would get
        // "0008" and a Thai Buddhist user "2569" for the year 2026. That breaks
        // both the filename and the chronological sort it is meant to provide.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
