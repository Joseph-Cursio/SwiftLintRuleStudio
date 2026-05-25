//
//  Violation.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Filter criteria for violations
public struct ViolationFilter: Sendable {
    public var ruleIDs: [String]?
    public var filePaths: [String]?
    public var severities: [Severity]?
    // nil = no filter, true = suppressed only, false = unsuppressed only
    // swiftlint:disable:next discouraged_optional_boolean
    public var suppressedOnly: Bool?
    public var dateRange: ClosedRange<Date>?

    nonisolated public init(
        ruleIDs: [String]? = nil,
        filePaths: [String]? = nil,
        severities: [Severity]? = nil,
        // swiftlint:disable:next discouraged_optional_boolean
        suppressedOnly: Bool? = nil,
        dateRange: ClosedRange<Date>? = nil
    ) {
        self.ruleIDs = ruleIDs
        self.filePaths = filePaths
        self.severities = severities
        self.suppressedOnly = suppressedOnly
        self.dateRange = dateRange
    }

    nonisolated public static var all: Self {
        Self()
    }
}

/// Represents a SwiftLint rule violation
public struct Violation: Identifiable, Codable, Hashable, Sendable {
    nonisolated public let id: UUID
    nonisolated public let ruleID: String
    nonisolated public let filePath: String
    nonisolated public let line: Int
    nonisolated public let column: Int?
    nonisolated public let severity: Severity
    nonisolated public let message: String
    nonisolated public let detectedAt: Date
    nonisolated public var resolvedAt: Date?
    nonisolated public var suppressed: Bool
    nonisolated public var suppressionReason: String?

    nonisolated public init(
        ruleID: String,
        filePath: String,
        line: Int,
        severity: Severity,
        message: String,
        id: UUID = UUID(),
        column: Int? = nil,
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
