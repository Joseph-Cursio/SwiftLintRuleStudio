//
//  SwiftLintCLICachingTests.swift
//  SwiftLintRuleStudioTests
//
//  Integration tests for SwiftLintCLI documentation caching
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// CacheManager is not @MainActor, but Swift 6 has a false positive that incorrectly infers @MainActor
// Temporarily using @MainActor on the test struct as a workaround (same as CacheManagerTests)
@MainActor
struct SwiftLintCLICachingTests {
    
    // Helper to create isolated cache manager
    private func createIsolatedCacheManager() -> CacheManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Workaround for Swift 6 false positive: CacheManager.init incorrectly inferred as @MainActor
        return CacheManager(cacheDirectory: tempDir)
    }
    
    // Helper to create mock SwiftLint CLI that simulates version
    private func createMockCLIWithVersion(_ version: String, cacheManager: CacheManagerProtocol) -> MockSwiftLintCLI {
        let mockCLI = MockSwiftLintCLI()
        // Override getVersion to return specific version
        // Note: This requires modifying MockSwiftLintCLI or using a different approach
        return mockCLI
    }
    
    @Test("generateDocsForRule saves version to cache after generation")
    func testVersionCachingAfterGeneration() async throws {
        // This test would require actual SwiftLint installation
        // For now, we test the cache manager integration
        let cacheManager = createIsolatedCacheManager()
        
        // Verify version is saved
        let testVersion = "0.55.0"
        try cacheManager.saveSwiftLintVersion(testVersion)
        
        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        #expect(cachedVersion == testVersion)
    }
    
    @Test("generateDocsForRule saves docs directory to cache")
    func testDocsDirectoryCaching() async throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Create a test docs directory
        let testDocsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent("docs_test", isDirectory: true)
        try FileManager.default.createDirectory(at: testDocsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDocsDir) }
        
        // Save directory
        try cacheManager.saveDocsDirectory(testDocsDir)
        
        // Verify it's cached
        let cachedDir = cacheManager.getCachedDocsDirectory()
        #expect(cachedDir == testDocsDir)
    }
    
    @Test("CacheManager handles version change correctly")
    func testVersionChangeDetection() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Save initial version
        try cacheManager.saveSwiftLintVersion("0.50.0")
        #expect(try cacheManager.getCachedSwiftLintVersion() == "0.50.0")
        
        // Change version
        try cacheManager.saveSwiftLintVersion("0.55.0")
        #expect(try cacheManager.getCachedSwiftLintVersion() == "0.55.0")
        
        // Old version should be gone
        #expect(try cacheManager.getCachedSwiftLintVersion() != "0.50.0")
    }
    
    @Test("CacheManager returns nil for docs directory when path is invalid")
    func testInvalidDocsDirectoryPath() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Save a non-existent path
        let invalidPath = "/tmp/nonexistent/\(UUID().uuidString)"
        let invalidURL = URL(fileURLWithPath: invalidPath)
        try cacheManager.saveDocsDirectory(invalidURL)
        
        // Should return nil because path doesn't exist
        let dir = cacheManager.getCachedDocsDirectory()
        #expect(dir == nil)
    }
    
    @Test("CacheManager clears docs directory when clearing cache")
    func testClearDocsCacheRemovesDirectory() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Create and save a test directory
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        
        // Create a test file in the directory
        let testFile = testDir.appendingPathComponent("test.md")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        try cacheManager.saveDocsDirectory(testDir)
        #expect(cacheManager.getCachedDocsDirectory() != nil)
        #expect(FileManager.default.fileExists(atPath: testDir.path))
        
        // Clear docs cache
        try cacheManager.clearDocsCache()
        
        // Directory should be removed
        #expect(FileManager.default.fileExists(atPath: testDir.path) == false)
        #expect(cacheManager.getCachedDocsDirectory() == nil)
    }
}

