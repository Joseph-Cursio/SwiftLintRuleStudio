//
//  AnalysisResult.swift
//  SwiftLintRuleStudio
//

import Foundation

/// Result of a workspace analysis
public struct AnalysisResult {
    /// Violations found during analysis
    public let violations: [Violation]
    /// Number of Swift files analyzed
    public let filesAnalyzed: Int
    /// Total elapsed time of the analysis
    public let duration: TimeInterval
    /// Timestamp when analysis began
    public let startedAt: Date
    /// Timestamp when analysis finished
    public let completedAt: Date
    /// SHA-256 hash of the config file used, if any
    public let configHash: String?

    /// Creates a new analysis result
    public init(
        violations: [Violation],
        filesAnalyzed: Int,
        duration: TimeInterval,
        startedAt: Date,
        completedAt: Date,
        configHash: String? = nil
    ) {
        self.violations = violations
        self.filesAnalyzed = filesAnalyzed
        self.duration = duration
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.configHash = configHash
    }
}
