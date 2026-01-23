//
//  Violation.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint rule violation
struct Violation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ruleID: String
    let filePath: String
    let line: Int
    let column: Int?
    let severity: Severity
    let message: String
    let detectedAt: Date
    var resolvedAt: Date?
    var suppressed: Bool
    var suppressionReason: String?
    
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
    var ruleIDs: [String]?
    var filePaths: [String]?
    var severities: [Severity]?
    var suppressedOnly: Bool?
    var dateRange: ClosedRange<Date>?
    
    static var all: ViolationFilter {
        ViolationFilter()
    }
}
