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

/// Cache operations are `nonisolated`: they are pure filesystem I/O with no shared
/// mutable state, so conformers (and `any CacheManagerProtocol`) can be used from any
/// isolation domain — including `SwiftLintCLIActor`. The requirements are marked
/// explicitly because the Core layer runs under `defaultIsolation(MainActor.self)`,
/// which would otherwise pin them to the main actor and force callers off the actor.
public protocol CacheManagerProtocol: Sendable {
    nonisolated func loadCachedRules() throws -> [Rule]
    nonisolated func saveCachedRules(_ rules: [Rule]) throws
    nonisolated func clearCache() throws
    nonisolated func getCachedSwiftLintVersion() throws -> String?
    nonisolated func saveSwiftLintVersion(_ version: String) throws
    nonisolated func getCachedDocsDirectory() -> URL?
    nonisolated func saveDocsDirectory(_ url: URL) throws
    nonisolated func clearDocsCache() throws
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
