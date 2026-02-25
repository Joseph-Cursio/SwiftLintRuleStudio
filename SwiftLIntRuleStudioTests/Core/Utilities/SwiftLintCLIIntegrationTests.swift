//
//  SwiftLintCLIIntegrationTests.swift
//  SwiftLintRuleStudioTests
//
//  Integration tests for SwiftLintCLI documentation generation and caching
//  These tests require SwiftLint to be installed
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// SwiftLintCLI is an actor (not @MainActor), but CacheManager has Swift 6 false positive
// Temporarily using @MainActor on the test struct as a workaround (same as CacheManagerTests)
@MainActor
struct SwiftLintCLIIntegrationTests {
    
    // Helper to check if SwiftLint is available
    nonisolated private func isSwiftLintAvailable() -> Bool {
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",
            "/usr/local/bin/swiftlint",
            "/usr/bin/swiftlint"
        ]
        return possiblePaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    // Helper to create isolated cache manager for test isolation
    // Each test gets its own cache directory to prevent race conditions and state leakage
    private func createIsolatedCacheManager() -> (CacheManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent("SwiftLintCLIIntegrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (CacheManager(cacheDirectory: tempDir), tempDir)
    }
    
    // Helper to cleanup cache directory after test
    private func cleanupCacheDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    @Test("generateDocsForRule generates documentation for a rule")
    func testGenerateDocsForRule() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = SwiftLintCLI(cacheManager: cacheManager)
        
        // Generate docs for a common rule
        let markdown = try await cli.generateDocsForRule(ruleId: "empty_count")
        
        // Verify we got markdown content
        #expect(!markdown.isEmpty)
        #expect(markdown.contains("empty_count") || markdown.contains("Empty Count"))
        
        // Verify version was cached
        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        let unwrappedVersion = try #require(cachedVersion)
        #expect(!unwrappedVersion.isEmpty)
        
        // Verify docs directory was cached
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        #expect(FileManager.default.fileExists(atPath: cachedDir.path))
    }
    
    @Test("generateDocsForRule caches documentation and reuses it")
    func testDocumentationCaching() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = await SwiftLintCLI(cacheManager: cacheManager)
        
        // First call - should generate
        let firstCall = try await cli.generateDocsForRule(ruleId: "empty_count")
        #expect(!firstCall.isEmpty)
        
        // Get the cached directory
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        
        // Verify the file exists in the cached directory
        let docFile = cachedDir.appendingPathComponent("empty_count.md")
        #expect(FileManager.default.fileExists(atPath: docFile.path))
        
        // Second call - should use cache (same version)
        // Note: This will still call generate-docs but should find existing files
        // The real caching benefit is that files persist across app restarts
        let secondCall = try await cli.generateDocsForRule(ruleId: "empty_count")
        #expect(!secondCall.isEmpty)
        
        // Content should be the same (from cache)
        #expect(firstCall == secondCall)
    }
    
    @Test("generateDocsForRule handles multiple rules")
    func testMultipleRulesDocumentation() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = SwiftLintCLI(cacheManager: cacheManager)
        
        // Generate docs for multiple rules
        let rule1 = try await cli.generateDocsForRule(ruleId: "empty_count")
        let rule2 = try await cli.generateDocsForRule(ruleId: "force_cast")
        let rule3 = try await cli.generateDocsForRule(ruleId: "line_length")
        
        // All should have content
        #expect(!rule1.isEmpty)
        #expect(!rule2.isEmpty)
        #expect(!rule3.isEmpty)
        
        // All should be different
        #expect(rule1 != rule2)
        #expect(rule2 != rule3)
        
        // Verify all files exist in cached directory
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        
        let file1 = cachedDir.appendingPathComponent("empty_count.md")
        let file2 = cachedDir.appendingPathComponent("force_cast.md")
        let file3 = cachedDir.appendingPathComponent("line_length.md")
        
        #expect(FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: file2.path))
        #expect(FileManager.default.fileExists(atPath: file3.path))
    }
    
    @Test("generateDocsForRule handles opt-in rules")
    func testOptInRuleDocumentation() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = SwiftLintCLI(cacheManager: cacheManager)
        
        // Generate docs for an opt-in rule (not enabled by default)
        let markdown = try await cli.generateDocsForRule(ruleId: "empty_count")
        
        // Should have content even though it's opt-in
        #expect(!markdown.isEmpty)
        #expect(markdown.contains("empty_count") || markdown.contains("Empty Count"))
    }
    
    @Test("generateDocsForRule saves version to cache")
    func testVersionCaching() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        // Use isolated cache for this test to ensure clean state
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = await SwiftLintCLI(cacheManager: cacheManager)
        
        // Initially no version cached
        let initialVersion = try cacheManager.getCachedSwiftLintVersion()
        #expect(initialVersion == nil)
        
        // Generate docs - should cache version
        _ = try await cli.generateDocsForRule(ruleId: "empty_count")
        
        // Version should now be cached
        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        let unwrappedVersion = try #require(cachedVersion)
        #expect(!unwrappedVersion.isEmpty)
        
        // Version should match actual SwiftLint version
        let actualVersion = try await cli.getVersion()
        #expect(unwrappedVersion == actualVersion)
    }
    
    @Test("generateDocsForRule saves docs directory to cache")
    func testDocsDirectoryCaching() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        // Use isolated cache for this test to ensure clean state
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = await SwiftLintCLI(cacheManager: cacheManager)
        
        // Initially no directory cached
        let initialDir = cacheManager.getCachedDocsDirectory()
        #expect(initialDir == nil)
        
        // Generate docs - should cache directory
        _ = try await cli.generateDocsForRule(ruleId: "empty_count")
        
        // Directory should now be cached
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        #expect(FileManager.default.fileExists(atPath: cachedDir.path))
        
        // Directory should contain the generated markdown file
        let docFile = cachedDir.appendingPathComponent("empty_count.md")
        #expect(FileManager.default.fileExists(atPath: docFile.path))
    }
    
    @Test("generateDocsForRule handles file system delays")
    func testFileSystemDelayHandling() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = SwiftLintCLI(cacheManager: cacheManager)
        
        // Generate docs - the retry logic should handle any file system delays
        let markdown = try await cli.generateDocsForRule(ruleId: "empty_count")
        
        // Should successfully get content even with potential delays
        #expect(!markdown.isEmpty)
        
        // Verify file exists in cached directory
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        
        let docFile = cachedDir.appendingPathComponent("empty_count.md")
        #expect(FileManager.default.fileExists(atPath: docFile.path))
        
        // File should be readable
        let content = try? String(contentsOf: docFile, encoding: .utf8)
        #expect(content != nil)
        let unwrappedContent = try #require(content)
        #expect(!unwrappedContent.isEmpty)
    }
    
    @Test("generateDocsForRule generates docs for all rules, not just enabled")
    func testAllRulesDocumentation() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        let cli = SwiftLintCLI(cacheManager: cacheManager)
        
        // Generate docs for an opt-in rule (not enabled by default)
        let optInRule = try await cli.generateDocsForRule(ruleId: "empty_count")
        #expect(!optInRule.isEmpty)
        
        // Generate docs for a default-enabled rule
        let defaultRule = try await cli.generateDocsForRule(ruleId: "force_cast")
        #expect(!defaultRule.isEmpty)
        
        // Both should have documentation
        #expect(optInRule != defaultRule)
        
        // Verify both files exist in cached directory
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        
        let optInFile = cachedDir.appendingPathComponent("empty_count.md")
        let defaultFile = cachedDir.appendingPathComponent("force_cast.md")
        
        #expect(FileManager.default.fileExists(atPath: optInFile.path))
        #expect(FileManager.default.fileExists(atPath: defaultFile.path))
    }
    
    @Test("Cache persists across CLI instances")
    func testCachePersistence() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { cleanupCacheDirectory(cacheDir) }
        
        // First CLI instance - generate docs
        let cli1 = SwiftLintCLI(cacheManager: cacheManager)
        _ = try await cli1.generateDocsForRule(ruleId: "empty_count")
        
        // Verify version and directory are cached
        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        let unwrappedVersion = try #require(cachedVersion)
        let cachedDir = try #require(cacheManager.getCachedDocsDirectory())
        
        // Create second CLI instance with same cache manager
        let cli2 = await SwiftLintCLI(cacheManager: cacheManager)
        
        // Should still have cached version and directory
        let version2 = try cacheManager.getCachedSwiftLintVersion()
        let unwrappedVersion2 = try #require(version2)
        let dir2 = try #require(cacheManager.getCachedDocsDirectory())
        #expect(unwrappedVersion2 == unwrappedVersion)
        #expect(dir2 == cachedDir)
        
        // Should be able to read from cached directory
        let docFile = cachedDir.appendingPathComponent("empty_count.md")
        #expect(FileManager.default.fileExists(atPath: docFile.path))
    }
}
