//
//  FileTracker+Testing.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import LintStudioCore

// Extension to FileTracker for test isolation
public extension FileTracker {
    /// Creates a FileTracker with isolated cache file for testing
    /// Uses UUID to ensure complete isolation between tests
    /// Note: FileTracker is @MainActor, so this must be called from MainActor context
    @MainActor
    static func createForTesting() -> FileTracker {
        let cacheURL = TestTempDirectory.make("filetracker")
            .appendingPathComponent("file_tracker_cache.json")
        return FileTracker(cacheURL: cacheURL)
    }
}
