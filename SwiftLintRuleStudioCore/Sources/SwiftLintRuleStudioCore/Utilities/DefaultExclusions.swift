//
//  DefaultExclusions.swift
//  SwiftLintRuleStudio
//
//  Canonical list of directories to exclude from SwiftLint analysis.
//  Used by ImpactSimulator, WorkspaceAnalyzer, and WorkspaceManager
//  to ensure consistent behavior across all analysis paths.
//

import Foundation

/// Canonical directory exclusions for SwiftLint analysis
public enum DefaultExclusions {
    /// Canonical list of directory names to exclude from SwiftLint analysis.
    /// These are build artifacts, dependency caches, and metadata directories
    /// that contain third-party or generated code.
    public static let directories: [String] = [
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
    public static let pathPatterns: [String] = directories.map { "/\($0)/" }

    /// Merge default exclusions with an existing exclusion list.
    /// Preserves the order and entries of `existing`, then appends any
    /// defaults that are not already present (case-sensitive comparison).
    ///
    /// Deduplication happens only *across the seam*: a default already named in
    /// `existing` is not appended a second time. `existing` itself is copied
    /// verbatim, so any repeats the caller passed in survive — the result is not
    /// a deduplicated list, and cannot be one without breaking the guarantee that
    /// `existing` is preserved as a prefix.
    /// - Parameter existing: The user's current exclusion list (may be nil or empty).
    /// - Returns: `existing` verbatim, followed by the defaults it does not
    ///   already contain. Empty or `nil` input yields ``directories``.
    public static func mergedWith(existing: [String]?) -> [String] {
        guard let existing = existing, !existing.isEmpty else {
            return directories
        }

        let existingSet = Set(existing)
        let missingDefaults = directories.filter { !existingSet.contains($0) }
        return existing + missingDefaults
    }
}
