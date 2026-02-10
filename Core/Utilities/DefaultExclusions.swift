//
//  DefaultExclusions.swift
//  SwiftLintRuleStudio
//
//  Canonical list of directories to exclude from SwiftLint analysis.
//  Used by ImpactSimulator, WorkspaceAnalyzer, and WorkspaceManager
//  to ensure consistent behavior across all analysis paths.
//

import Foundation

enum DefaultExclusions {
    /// Canonical list of directory names to exclude from SwiftLint analysis.
    /// These are build artifacts, dependency caches, and metadata directories
    /// that contain third-party or generated code.
    static let directories: [String] = [
        ".build",
        "DerivedData",
        ".git",
        "Pods",
        "Carthage",
        ".swiftpm",
        "node_modules",
        "Build"
    ]

    /// Path-contains patterns for filtering file paths during enumeration.
    /// Each entry is formatted as `/name/` so it matches only full path components.
    static let pathPatterns: [String] = directories.map { "/\($0)/" }

    /// Merge default exclusions with an existing exclusion list.
    /// Preserves the order and entries of `existing`, then appends any
    /// defaults that are not already present (case-sensitive comparison).
    /// - Parameter existing: The user's current exclusion list (may be nil or empty).
    /// - Returns: A deduplicated list containing all existing entries followed by missing defaults.
    static func mergedWith(existing: [String]?) -> [String] {
        guard let existing = existing, !existing.isEmpty else {
            return directories
        }

        let existingSet = Set(existing)
        let missingDefaults = directories.filter { !existingSet.contains($0) }
        return existing + missingDefaults
    }
}
