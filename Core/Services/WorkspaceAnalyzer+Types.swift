//
//  WorkspaceAnalyzer+Types.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import CryptoKit

/// Result of a workspace analysis
struct AnalysisResult {
    let violations: [Violation]
    let filesAnalyzed: Int
    let duration: TimeInterval
    let startedAt: Date
    let completedAt: Date
    let configHash: String?

    init(
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
struct AnalysisProgress {
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int?
    let violationsFound: Int
    let isComplete: Bool

    var progress: Double {
        guard let total = totalFiles, total > 0 else { return 0.0 }
        return Double(filesProcessed) / Double(total)
    }
}

// MARK: - Errors

enum WorkspaceAnalyzerError: LocalizedError {
    case analysisFailed(String)
    case invalidOutput(String)
    case workspaceNotFound
    case swiftLintNotFound

    var errorDescription: String? {
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
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
