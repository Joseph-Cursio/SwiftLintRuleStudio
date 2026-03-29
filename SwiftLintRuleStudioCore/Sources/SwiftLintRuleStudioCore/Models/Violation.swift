//
//  Violation.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint rule violation
public struct Violation: Identifiable, Codable, Hashable, Sendable {
    public nonisolated let id: UUID
    public nonisolated let ruleID: String
    public nonisolated let filePath: String
    public nonisolated let line: Int
    public nonisolated let column: Int?
    public nonisolated let severity: Severity
    public nonisolated let message: String
    public nonisolated let detectedAt: Date
    public nonisolated var resolvedAt: Date?
    public nonisolated var suppressed: Bool
    public nonisolated var suppressionReason: String?

    public nonisolated init(
        id: UUID = UUID(),
        ruleID: String,
        filePath: String,
        line: Int,
        column: Int? = nil,
        severity: Severity,
        message: String,
        detectedAt: Date = Date.now,
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
public struct ViolationFilter: Sendable {
    public var ruleIDs: [String]?
    public var filePaths: [String]?
    public var severities: [Severity]?
    public var suppressedOnly: Bool?
    public var dateRange: ClosedRange<Date>?

    public nonisolated init(
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

    public nonisolated static var all: ViolationFilter {
        ViolationFilter()
    }
}
