//
//  WorkspaceAnalyzer+Types.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import CryptoKit

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

/// Analysis progress information
public struct AnalysisProgress {
    /// Name of the file currently being analyzed
    public let currentFile: String?
    /// Number of files processed so far
    public let filesProcessed: Int
    /// Total number of files to analyze, if known
    public let totalFiles: Int?
    /// Running count of violations found
    public let violationsFound: Int
    /// Whether the analysis has finished
    public let isComplete: Bool

    /// Fraction of files processed (0.0 to 1.0)
    public var progress: Double {
        guard let total = totalFiles, total > 0 else { return 0.0 }
        return Double(filesProcessed) / Double(total)
    }

    /// Creates a new progress snapshot
    public init(
        currentFile: String?,
        filesProcessed: Int,
        totalFiles: Int?,
        violationsFound: Int,
        isComplete: Bool
    ) {
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.violationsFound = violationsFound
        self.isComplete = isComplete
    }
}

// MARK: - Errors

/// Errors that can occur during workspace analysis
public enum WorkspaceAnalyzerError: LocalizedError, Sendable {
    case analysisFailed(String)
    case invalidOutput(String)
    case workspaceNotFound
    case swiftLintNotFound

    public var errorDescription: String? {
        switch self {
        case .analysisFailed(let message):
            return "Analysis failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid SwiftLint output: \(message)"
        case .workspaceNotFound:
            return "Workspace not found"
        case .swiftLintNotFound:
            return "SwiftLint binary not found"
        }
    }
}

// MARK: - Data Extension

public extension Data {
    /// Computes a SHA-256 hex digest of this data
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
