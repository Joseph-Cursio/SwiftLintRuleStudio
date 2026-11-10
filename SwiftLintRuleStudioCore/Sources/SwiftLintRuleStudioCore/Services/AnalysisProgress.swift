//
//  AnalysisProgress.swift
//  SwiftLintRuleStudio
//

import CryptoKit
import Foundation

/// Analysis progress information
///
/// `nonisolated` so a generator can build one off the main actor; every field is a value.
nonisolated public struct AnalysisProgress: Sendable {
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
    ///
    /// Clamped, because nothing else keeps it in range: a snapshot whose count runs past its total
    /// — a file counted twice, a total estimated low — gave a fraction above 1.0, which
    /// swift-infer's `documented-range` law found against this comment.
    public var progress: Double {
        guard let total = totalFiles, total > 0 else { return 0.0 }
        return min(max(Double(filesProcessed) / Double(total), 0.0), 1.0)
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
