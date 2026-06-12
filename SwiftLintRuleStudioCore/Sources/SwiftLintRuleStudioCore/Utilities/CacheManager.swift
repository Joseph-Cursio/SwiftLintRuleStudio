//
//  CacheManager.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//
//  SwiftLint-specific cache: rules catalog, swiftlint version, and the
//  generated-docs directory. A thin domain wrapper over LintStudioCore.FileCache.
//

import Foundation
import LintStudioCore

public protocol CacheManagerProtocol: Sendable {
    func loadCachedRules() throws -> [Rule]
    func saveCachedRules(_ rules: [Rule]) throws
    func clearCache() throws
    func getCachedSwiftLintVersion() throws -> String?
    func saveSwiftLintVersion(_ version: String) throws
    func getCachedDocsDirectory() -> URL?
    func saveDocsDirectory(_ url: URL) throws
    func clearDocsCache() throws
}

public struct CacheManager: CacheManagerProtocol {
    private let cache: FileCache

    private let rulesCacheFile = "rules_cache.json"
    private let versionCacheFile = "swiftlint_version.txt"
    private let docsDirectoryCacheFile = "docs_directory.txt"

    public init(cacheDirectory: URL? = nil) {
        cache = FileCache(appIdentifier: "SwiftLintRuleStudio", cacheDirectory: cacheDirectory)
    }

    nonisolated public func loadCachedRules() throws -> [Rule] {
        try cache.loadCodable([Rule].self, from: rulesCacheFile) ?? []
    }

    nonisolated public func saveCachedRules(_ rules: [Rule]) throws {
        try cache.saveCodable(rules, to: rulesCacheFile)
    }

    nonisolated public func clearCache() throws {
        try cache.removeFile(rulesCacheFile)
    }

    // MARK: - SwiftLint Version Caching

    nonisolated public func getCachedSwiftLintVersion() throws -> String? {
        try cache.loadString(from: versionCacheFile)
    }

    nonisolated public func saveSwiftLintVersion(_ version: String) throws {
        try cache.saveString(version, to: versionCacheFile)
    }

    // MARK: - Documentation Directory Caching

    nonisolated public func getCachedDocsDirectory() -> URL? {
        let pathString = try? cache.loadString(from: docsDirectoryCacheFile)
        guard let pathString,
              !pathString.isEmpty,
              FileManager.default.fileExists(atPath: pathString) else {
            return nil
        }
        return URL(fileURLWithPath: pathString)
    }

    nonisolated public func saveDocsDirectory(_ url: URL) throws {
        try cache.saveString(url.path, to: docsDirectoryCacheFile)
    }

    nonisolated public func clearDocsCache() throws {
        // Remove the generated docs directory itself, if still present.
        if let docsDir = getCachedDocsDirectory() {
            try? FileManager.default.removeItem(at: docsDir)
        }
        // Remove the pointer file.
        try cache.removeFile(docsDirectoryCacheFile)
    }
}
