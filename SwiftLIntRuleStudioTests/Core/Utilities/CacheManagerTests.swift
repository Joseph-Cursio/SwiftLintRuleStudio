//
//  CacheManagerTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// CacheManager is not @MainActor, but Swift 6 false positive requires it temporarily
@MainActor
struct CacheManagerTests {
    
    // Helper to create isolated cache directory for each test
    private func createIsolatedCacheManager() -> CacheManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return CacheManager(cacheDirectory: tempDir)
    }
    
    @Test("CacheManager can save and load rules")
    func testCacheSaveAndLoad() throws {
        let cacheManager = createIsolatedCacheManager()
        
        let rules = [
            Rule(
                id: "rule1",
                name: "Rule 1",
                description: "First rule",
                category: .style,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: true,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            ),
            Rule(
                id: "rule2",
                name: "Rule 2",
                description: "Second rule",
                category: .lint,
                isOptIn: true,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            )
        ]
        
        // Save rules
        try cacheManager.saveCachedRules(rules)
        
        // Load rules
        let loadedRules = try cacheManager.loadCachedRules()
        
        #expect(loadedRules.count == 2)
        #expect(loadedRules[0].id == "rule1")
        #expect(loadedRules[1].id == "rule2")
    }
    
    @Test("CacheManager returns empty array when cache doesn't exist")
    func testCacheLoadWhenEmpty() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Clear cache first
        try? cacheManager.clearCache()
        
        // Try to load (should return empty array, not throw)
        let rules = try cacheManager.loadCachedRules()
        #expect(rules.isEmpty)
    }
    
    @Test("CacheManager can clear cache")
    func testCacheClear() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // First, ensure cache is empty
        try? cacheManager.clearCache()
        
        let rules = [
            Rule(
                id: "test_rule",
                name: "Test",
                description: "Test rule",
                category: .style,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: true,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            )
        ]
        
        // Save and verify
        try cacheManager.saveCachedRules(rules)
        let loadedBefore = try cacheManager.loadCachedRules()
        #expect(loadedBefore.count == 1)
        
        // Clear and verify
        try cacheManager.clearCache()
        let loadedAfter = try cacheManager.loadCachedRules()
        #expect(loadedAfter.isEmpty)
    }
    
    // MARK: - Version Caching Tests
    
    @Test("CacheManager can save and load SwiftLint version")
    func testVersionCaching() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Initially should be nil
        let initialVersion = try cacheManager.getCachedSwiftLintVersion()
        #expect(initialVersion == nil)
        
        // Save version
        try cacheManager.saveSwiftLintVersion("0.55.0")
        
        // Load version
        let cachedVersion = try cacheManager.getCachedSwiftLintVersion()
        #expect(cachedVersion == "0.55.0")
    }
    
    @Test("CacheManager returns nil for version when not cached")
    func testVersionCacheWhenEmpty() throws {
        let cacheManager = createIsolatedCacheManager()
        
        let version = try cacheManager.getCachedSwiftLintVersion()
        #expect(version == nil)
    }
    
    @Test("CacheManager can update SwiftLint version")
    func testVersionUpdate() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Save initial version
        try cacheManager.saveSwiftLintVersion("0.50.0")
        #expect(try cacheManager.getCachedSwiftLintVersion() == "0.50.0")
        
        // Update version
        try cacheManager.saveSwiftLintVersion("0.55.0")
        #expect(try cacheManager.getCachedSwiftLintVersion() == "0.55.0")
    }
    
    // MARK: - Docs Directory Caching Tests
    
    @Test("CacheManager can save and load docs directory")
    func testDocsDirectoryCaching() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Create a test directory
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Initially should be nil
        let initialDir = cacheManager.getCachedDocsDirectory()
        #expect(initialDir == nil)
        
        // Save directory
        try cacheManager.saveDocsDirectory(testDir)
        
        // Load directory
        let cachedDir = cacheManager.getCachedDocsDirectory()
        #expect(cachedDir == testDir)
    }
    
    @Test("CacheManager returns nil for docs directory when not cached")
    func testDocsDirectoryCacheWhenEmpty() {
        let cacheManager = createIsolatedCacheManager()
        
        let dir = cacheManager.getCachedDocsDirectory()
        #expect(dir == nil)
    }
    
    @Test("CacheManager returns nil for docs directory when path doesn't exist")
    func testDocsDirectoryCacheWhenPathMissing() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Save a non-existent directory path
        let nonExistentPath = "/tmp/nonexistent/\(UUID().uuidString)"
        let nonExistentURL = URL(fileURLWithPath: nonExistentPath)
        try cacheManager.saveDocsDirectory(nonExistentURL)
        
        // Should return nil because path doesn't exist
        let dir = cacheManager.getCachedDocsDirectory()
        #expect(dir == nil)
    }
    
    @Test("CacheManager can clear docs cache")
    func testClearDocsCache() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Create and save a test directory
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        
        try cacheManager.saveDocsDirectory(testDir)
        #expect(cacheManager.getCachedDocsDirectory() != nil)
        
        // Clear docs cache
        try cacheManager.clearDocsCache()
        
        // Should be nil after clearing
        #expect(cacheManager.getCachedDocsDirectory() == nil)
        
        // Directory should be removed
        #expect(FileManager.default.fileExists(atPath: testDir.path) == false)
    }
    
    @Test("CacheManager clearDocsCache handles missing directory gracefully")
    func testClearDocsCacheWhenMissing() throws {
        let cacheManager = createIsolatedCacheManager()
        
        // Should not throw when clearing non-existent cache
        try cacheManager.clearDocsCache()
        #expect(cacheManager.getCachedDocsDirectory() == nil)
    }
}
