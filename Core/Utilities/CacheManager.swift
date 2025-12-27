//
//  CacheManager.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

protocol CacheManagerProtocol: Sendable {
    func loadCachedRules() throws -> [Rule]
    func saveCachedRules(_ rules: [Rule]) throws
    func clearCache() throws
    func getCachedSwiftLintVersion() throws -> String?
    func saveSwiftLintVersion(_ version: String) throws
    func getCachedDocsDirectory() -> URL?
    func saveDocsDirectory(_ url: URL) throws
    func clearDocsCache() throws
}

struct CacheManager: CacheManagerProtocol {
    private let cacheDirectory: URL
    private let rulesCacheFile: URL
    private let versionCacheFile: URL
    private let docsDirectoryCacheFile: URL
    
    init(cacheDirectory: URL? = nil) {
        if let customDirectory = cacheDirectory {
            self.cacheDirectory = customDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.cacheDirectory = appSupport.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
        }
        rulesCacheFile = self.cacheDirectory.appendingPathComponent("rules_cache.json")
        versionCacheFile = self.cacheDirectory.appendingPathComponent("swiftlint_version.txt")
        docsDirectoryCacheFile = self.cacheDirectory.appendingPathComponent("docs_directory.txt")
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    nonisolated func loadCachedRules() throws -> [Rule] {
        guard FileManager.default.fileExists(atPath: rulesCacheFile.path) else {
            return []
        }
        
        let data = try Data(contentsOf: rulesCacheFile)
        let decoder = JSONDecoder()
        return try decoder.decode([Rule].self, from: data)
    }
    
    nonisolated func saveCachedRules(_ rules: [Rule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: rulesCacheFile)
    }
    
    nonisolated func clearCache() throws {
        // Only try to remove if file exists
        if FileManager.default.fileExists(atPath: rulesCacheFile.path) {
            try FileManager.default.removeItem(at: rulesCacheFile)
        }
    }
    
    // MARK: - SwiftLint Version Caching
    
    nonisolated func getCachedSwiftLintVersion() throws -> String? {
        guard FileManager.default.fileExists(atPath: versionCacheFile.path) else {
            return nil
        }
        return try String(contentsOf: versionCacheFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated func saveSwiftLintVersion(_ version: String) throws {
        try version.write(to: versionCacheFile, atomically: true, encoding: .utf8)
        print("📝 Cached SwiftLint version: \(version)")
    }
    
    // MARK: - Documentation Directory Caching
    
    nonisolated func getCachedDocsDirectory() -> URL? {
        guard FileManager.default.fileExists(atPath: docsDirectoryCacheFile.path),
              let pathString = try? String(contentsOf: docsDirectoryCacheFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !pathString.isEmpty,
              FileManager.default.fileExists(atPath: pathString) else {
            return nil
        }
        return URL(fileURLWithPath: pathString)
    }
    
    nonisolated func saveDocsDirectory(_ url: URL) throws {
        try url.path.write(to: docsDirectoryCacheFile, atomically: true, encoding: .utf8)
        print("📝 Cached docs directory: \(url.path)")
    }
    
    nonisolated func clearDocsCache() throws {
        // Remove cached docs directory if it exists
        if let docsDir = getCachedDocsDirectory() {
            try? FileManager.default.removeItem(at: docsDir)
        }
        
        // Remove cache file
        if FileManager.default.fileExists(atPath: docsDirectoryCacheFile.path) {
            try FileManager.default.removeItem(at: docsDirectoryCacheFile)
        }
    }
}

