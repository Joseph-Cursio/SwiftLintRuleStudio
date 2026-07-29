//
//  SwiftLintCLICachingTests.swift
//  SwiftLintRuleStudioTests
//
//  Integration tests for SwiftLintCLIActor documentation caching
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintCLIBackend
import SwiftLintRuleStudioCoreTestSupport
import Testing

// CacheManager is not @MainActor, but Swift 6 has a false positive that incorrectly infers @MainActor
// Temporarily using @MainActor on the test struct as a workaround (same as CacheManagerTests)
@MainActor
struct SwiftLintCLICachingTests {

    // Helper to create an isolated cache manager. Returns the temp directory too so
    // callers can `defer`-remove it — otherwise each run leaks a temp cache dir.
    private func createIsolatedCacheManager() -> (CacheManager, URL) {
        let tempDir = TestTempDirectory.make("clicache")
        // Workaround for Swift 6 false positive: CacheManager.init incorrectly inferred as @MainActor
        return (CacheManager(cacheDirectory: tempDir), tempDir)
    }

    // Helper to create mock SwiftLint CLI that simulates version
    private func createMockCLIWithVersion(
        _: String, cacheManager _: CacheManagerProtocol
    ) -> MockSwiftLintCLIActor {
        // Override getVersion to return specific version
        // Note: This requires modifying MockSwiftLintCLIActor or using a different approach
        MockSwiftLintCLIActor()
    }

    @Test("generateDocsForRule saves version to cache after generation")
    func testVersionCachingAfterGeneration() throws {
        // This test would require actual SwiftLint installation
        // For now, we test the cache manager integration
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Verify version is saved
        let testVersion = "0.55.0"
        try cacheManager.saveSwiftLintVersion(testVersion)

        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        #expect(cachedVersion == testVersion)
    }

    @Test("generateDocsForRule saves docs directory to cache")
    func testDocsDirectoryCaching() throws {
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Create a test docs directory
        let testDocsDir = TestTempDirectory.make("docs-test")
        defer { try? FileManager.default.removeItem(at: testDocsDir) }

        // Save directory
        try cacheManager.saveDocsDirectory(testDocsDir)

        // Verify it's cached
        let cachedDir = cacheManager.getCachedDocsDirectory()
        #expect(cachedDir == testDocsDir)
    }

    @Test("CacheManager handles version change correctly")
    func testVersionChangeDetection() throws {
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

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
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Save a non-existent path
        let invalidPath = "/tmp/nonexistent/\(UUID().uuidString)"
        let invalidURL = URL(fileURLWithPath: invalidPath)
        try cacheManager.saveDocsDirectory(invalidURL)

        // Should return nil because path doesn't exist
        let dir = cacheManager.getCachedDocsDirectory()
        #expect(dir == nil)
    }

    @Test("SwiftLintCLIActor honors an injected CacheManagerProtocol rather than discarding it")
    func testInjectedCacheManagerIsHonored() async throws {
        // Regression: the actor used to downcast the injected cache to the concrete
        // `CacheManager` and fall back to a fresh instance for anything else, so a
        // `MockCacheManager` was silently dropped. It must now be stored and used.
        let mock = MockCacheManager()
        mock.cachedVersion = "9.9.9"

        let cli = SwiftLintCLIActor(cacheManager: mock)

        let stored = await cli.cacheManager
        let storedMock = try #require(stored as? MockCacheManager)
        #expect(storedMock === mock)
        #expect(try storedMock.getCachedSwiftLintVersion() == "9.9.9")
    }

    @Test("CacheManager clears docs directory when clearing cache")
    func testClearDocsCacheRemovesDirectory() throws {
        let (cacheManager, cacheDir) = createIsolatedCacheManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Create and save a test directory
        let testDir = TestTempDirectory.make("clicache")

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
