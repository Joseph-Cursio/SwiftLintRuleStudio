//
//  CacheManager+Testing.swift
//  SwiftLintRuleStudioTests
//

@testable import SwiftLintRuleStudioCore

// Extension to CacheManager for test isolation
public extension CacheManager {
    /// Creates a CacheManager with isolated cache directory for testing
    /// Uses UUID to ensure complete isolation between tests
    static func createForTesting() -> CacheManager {
        CacheManager(cacheDirectory: TestTempDirectory.make("cache"))
    }
}
