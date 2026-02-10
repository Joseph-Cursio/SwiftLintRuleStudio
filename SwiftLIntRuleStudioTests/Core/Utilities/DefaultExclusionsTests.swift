//
//  DefaultExclusionsTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the shared DefaultExclusions utility.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct DefaultExclusionsTests {

    // MARK: - directories

    @Test("directories contains all expected entries")
    func directoriesContainsExpectedEntries() {
        let expected: Set<String> = [
            ".build", "DerivedData", ".git", "Pods",
            "Carthage", ".swiftpm", "node_modules", "Build"
        ]
        #expect(Set(DefaultExclusions.directories) == expected)
    }

    @Test("directories is not empty")
    func directoriesIsNotEmpty() {
        #expect(!DefaultExclusions.directories.isEmpty)
    }

    // MARK: - pathPatterns

    @Test("pathPatterns wraps each directory with slashes")
    func pathPatternsFormat() {
        for (index, pattern) in DefaultExclusions.pathPatterns.enumerated() {
            let dir = DefaultExclusions.directories[index]
            #expect(pattern == "/\(dir)/", "Pattern for \(dir) should be /\(dir)/ but got \(pattern)")
        }
    }

    @Test("pathPatterns count matches directories count")
    func pathPatternsCountMatchesDirectories() {
        #expect(DefaultExclusions.pathPatterns.count == DefaultExclusions.directories.count)
    }

    // MARK: - mergedWith(existing:)

    @Test("mergedWith nil returns full defaults")
    func mergedWithNil() {
        let result = DefaultExclusions.mergedWith(existing: nil)
        #expect(result == DefaultExclusions.directories)
    }

    @Test("mergedWith empty array returns full defaults")
    func mergedWithEmpty() {
        let result = DefaultExclusions.mergedWith(existing: [])
        #expect(result == DefaultExclusions.directories)
    }

    @Test("mergedWith custom entries preserves them and appends missing defaults")
    func mergedWithCustomEntries() {
        let existing = ["custom_dir", ".build"]
        let result = DefaultExclusions.mergedWith(existing: existing)

        // existing entries come first, in order
        #expect(result[0] == "custom_dir")
        #expect(result[1] == ".build")

        // all defaults are present
        for dir in DefaultExclusions.directories {
            #expect(result.contains(dir), "\(dir) should be present in merged result")
        }

        // no duplicates — .build should appear exactly once
        let buildCount = result.filter { $0 == ".build" }.count
        #expect(buildCount == 1, ".build should not be duplicated")
    }

    @Test("mergedWith all defaults returns same list unchanged")
    func mergedWithAllDefaults() {
        let result = DefaultExclusions.mergedWith(existing: DefaultExclusions.directories)
        #expect(result == DefaultExclusions.directories)
    }

    @Test("mergedWith preserves user ordering")
    func mergedWithPreservesOrder() {
        let existing = ["Pods", "DerivedData", "my_vendor"]
        let result = DefaultExclusions.mergedWith(existing: existing)

        // User entries stay at their positions
        #expect(result[0] == "Pods")
        #expect(result[1] == "DerivedData")
        #expect(result[2] == "my_vendor")

        // Remaining defaults follow
        let appended = Array(result.dropFirst(3))
        for dir in DefaultExclusions.directories where !existing.contains(dir) {
            #expect(appended.contains(dir), "\(dir) should be appended after user entries")
        }
    }
}
