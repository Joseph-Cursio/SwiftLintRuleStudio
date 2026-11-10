//
//  WorkspaceAnalyzerError.swift
//  SwiftLintRuleStudio
//

import Foundation

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
