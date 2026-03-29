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
    public let violations: [Violation]
    public let filesAnalyzed: Int
    public let duration: TimeInterval
    public let startedAt: Date
    public let completedAt: Date
    public let configHash: String?

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
    public let currentFile: String?
    public let filesProcessed: Int
    public let totalFiles: Int?
    public let violationsFound: Int
    public let isComplete: Bool

    public var progress: Double {
        guard let total = totalFiles, total > 0 else { return 0.0 }
        return Double(filesProcessed) / Double(total)
    }

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

extension Data {
    public func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
