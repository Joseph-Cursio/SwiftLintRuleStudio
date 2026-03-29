//
//  RuleRegistryTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities and mocks for RuleRegistry tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

public enum RulesTable: Sendable {
    nonisolated(unsafe) public static let border = "+------------------------------------------+--------+-------------+" +
        "------------------------+-------------+----------+----------------+---------------+"
    nonisolated(unsafe) public static let header = "| identifier | opt-in | correctable | enabled in your config | kind | analyzer | " +
        "uses sourcekit | configuration |"
}

public nonisolated func makeRulesTableData(rows: [String]) -> Data {
    let lines = [RulesTable.border, RulesTable.header, RulesTable.border] + rows + [RulesTable.border]
    return Data(lines.joined(separator: "\n").utf8)
}

public final class HangGate: @unchecked Sendable {
    nonisolated(unsafe) private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    public nonisolated func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    public nonisolated func open() {
        lock.lock()
        continuation?.resume()
        continuation = nil
        lock.unlock()
    }
}

public actor MockSwiftLintCLIActor: SwiftLintCLIProtocol {
    private let shouldFail: Bool
    private let mockRulesData: Data?
    private var mockLintOutput: Data = Data()
    private var shouldHang: Bool = false
    private let hangGate = HangGate()
    public var lintCommandHandler: (@Sendable (URL?, URL) async throws -> Data)?

    public init(shouldFail: Bool = false, mockRulesData: Data? = nil) {
        self.shouldFail = shouldFail
        self.mockRulesData = mockRulesData
    }

    public func setMockLintOutput(_ data: Data) {
        mockLintOutput = data
    }

    public func setShouldHang(_ value: Bool) {
        shouldHang = value
        if !value {
            hangGate.open()
        }
    }

    public func setLintCommandHandler(_ handler: @escaping @Sendable (URL?, URL) async throws -> Data) {
        lintCommandHandler = handler
    }

    public func detectSwiftLintPath() async throws -> URL {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.notFound
        }
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",
            "/usr/local/bin/swiftlint",
            "/usr/bin/swiftlint"
        ]
        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/local/bin/swiftlint")
    }

    public func executeRulesCommand() async throws -> Data {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        if let data = mockRulesData {
            return data
        }
        return makeRulesTableData(rows: [])
    }

    public func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        let mockDetail = """
        Force Cast (force_cast): Force casts should be avoided

        Configuration (YAML):

          force_cast:
            severity: error

        Triggering Examples (violations are marked with '↓'):

        Example #1

            NSNumber() ↓as! Int

        Non-Triggering Examples:

        Example #1

            if let number = value as? Int { }
        """
        return Data(mockDetail.utf8)
    }

    public func generateDocsForRule(ruleId: String) async throws -> String {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        return """
        # \(ruleId.capitalized)

        This is a test rule for \(ruleId).

        * **Identifier:** `\(ruleId)`
        * **Enabled by default:** Yes
        * **Supports autocorrection:** No

        ## Non Triggering Examples

        ```swift
        // Good code
        ```

        ## Triggering Examples

        ```swift
        // Bad code
        ```
        """
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        if shouldHang {
            return await withTaskCancellationHandler {
                await hangGate.wait()
                return Data()
            } onCancel: {
                hangGate.open()
            }
        }
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        if let handler = lintCommandHandler {
            return try await handler(configPath, workspacePath)
        }
        return mockLintOutput
    }

    public func getVersion() async throws -> String {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.invalidVersion
        }
        return "0.50.0"
    }
}

public actor RuleDetailsSwiftLintCLIActor: SwiftLintCLIProtocol {
    public let docs: String
    public let detail: String

    public init(docs: String, detail: String) {
        self.docs = docs
        self.detail = detail
    }

    public func detectSwiftLintPath() async throws -> URL {
        await Task.yield()
        throw SwiftLintError.notFound
    }

    public func executeRulesCommand() async throws -> Data {
        await Task.yield()
        return Data()
    }

    public func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        await Task.yield()
        return Data(detail.utf8)
    }

    public func generateDocsForRule(ruleId: String) async throws -> String {
        await Task.yield()
        return docs
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        await Task.yield()
        return Data()
    }

    public func getVersion() async throws -> String {
        await Task.yield()
        return "0.0.0"
    }
}

public final class MockCacheManager: CacheManagerProtocol, @unchecked Sendable {
    public var cachedRules: [Rule] = []
    public var shouldFailLoad = false
    public var shouldFailSave = false
    public var cachedVersion: String?
    public var cachedDocsDirectory: URL?

    public init() {}

    public func loadCachedRules() throws -> [Rule] {
        if shouldFailLoad {
            throw NSError(domain: "TestError", code: 1)
        }
        return cachedRules
    }

    public func saveCachedRules(_ rules: [Rule]) throws {
        if shouldFailSave {
            throw NSError(domain: "TestError", code: 1)
        }
        cachedRules = rules
    }

    public func clearCache() throws {
        cachedRules = []
    }

    public func getCachedSwiftLintVersion() throws -> String? {
        cachedVersion
    }

    public func saveSwiftLintVersion(_ version: String) throws {
        cachedVersion = version
    }

    public func getCachedDocsDirectory() -> URL? {
        cachedDocsDirectory
    }

    public func saveDocsDirectory(_ url: URL) throws {
        cachedDocsDirectory = url
    }

    public func clearDocsCache() throws {
        cachedDocsDirectory = nil
    }
}
