//
//  MockCacheManager.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore

// `nonisolated` on the class, not on each method: the package's
// `defaultIsolation(MainActor.self)` otherwise pins the stored properties to the
// main actor while the protocol's `nonisolated` requirements pull the methods off
// it, which Swift 6.4 rejects. `CacheManager` itself dodges this only by being a
// struct of `let`s.
nonisolated public final class MockCacheManager: CacheManagerProtocol, @unchecked Sendable {
    public var cachedRules: [Rule] = []
    public var shouldFailLoad = false
    public var shouldFailSave = false
    public var cachedVersion: String?
    public var cachedDocsDirectory: URL?

    public init() {
        // Declared only to make the initializer public.
    }

    nonisolated public func loadCachedRules() throws -> [Rule] {
        if shouldFailLoad {
            throw NSError(domain: "TestError", code: 1)
        }
        return cachedRules
    }

    nonisolated public func saveCachedRules(_ rules: [Rule]) throws {
        if shouldFailSave {
            throw NSError(domain: "TestError", code: 1)
        }
        cachedRules = rules
    }

    nonisolated public func clearCache() throws {
        cachedRules = []
    }

    nonisolated public func getCachedSwiftLintVersion() throws -> String? {
        cachedVersion
    }

    nonisolated public func saveSwiftLintVersion(_ version: String) throws {
        cachedVersion = version
    }

    nonisolated public func getCachedDocsDirectory() -> URL? {
        cachedDocsDirectory
    }

    nonisolated public func saveDocsDirectory(_ url: URL) throws {
        cachedDocsDirectory = url
    }

    nonisolated public func clearDocsCache() throws {
        cachedDocsDirectory = nil
    }
}
