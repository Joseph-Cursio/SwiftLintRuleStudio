//
//  Violation.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint rule violation
struct Violation: Identifiable, Codable, Hashable, Sendable {
    nonisolated let id: UUID
    nonisolated let ruleID: String
    nonisolated let filePath: String
    nonisolated let line: Int
    nonisolated let column: Int?
    nonisolated let severity: Severity
    nonisolated let message: String
    nonisolated let detectedAt: Date
    nonisolated var resolvedAt: Date?
    nonisolated var suppressed: Bool
    nonisolated var suppressionReason: String?
    
    nonisolated init(
        id: UUID = UUID(),
        ruleID: String,
        filePath: String,
        line: Int,
        column: Int? = nil,
        severity: Severity,
        message: String,
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil,
        suppressed: Bool = false,
        suppressionReason: String? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.filePath = filePath
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.suppressed = suppressed
        self.suppressionReason = suppressionReason
    }
}

/// Filter criteria for violations
struct ViolationFilter: Sendable {
    nonisolated var ruleIDs: [String]?
    nonisolated var filePaths: [String]?
    nonisolated var severities: [Severity]?
    nonisolated var suppressedOnly: Bool?
    nonisolated var dateRange: ClosedRange<Date>?

    nonisolated init(
        ruleIDs: [String]? = nil,
        filePaths: [String]? = nil,
        severities: [Severity]? = nil,
        suppressedOnly: Bool? = nil,
        dateRange: ClosedRange<Date>? = nil
    ) {
        self.ruleIDs = ruleIDs
        self.filePaths = filePaths
        self.severities = severities
        self.suppressedOnly = suppressedOnly
        self.dateRange = dateRange
    }

    nonisolated static var all: ViolationFilter {
        ViolationFilter()
    }
}
