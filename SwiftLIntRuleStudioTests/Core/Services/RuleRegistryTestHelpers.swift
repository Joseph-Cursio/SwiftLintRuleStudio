//
//  RuleRegistryTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities and mocks for RuleRegistry tests
//

import Foundation
@testable import SwiftLIntRuleStudio

enum RulesTable {
    static let border = "+------------------------------------------+--------+-------------+" +
        "------------------------+-------------+----------+----------------+---------------+"
    static let header = "| identifier | opt-in | correctable | enabled in your config | kind | analyzer | " +
        "uses sourcekit | configuration |"
}

func makeRulesTableData(rows: [String]) -> Data {
    let lines = [RulesTable.border, RulesTable.header, RulesTable.border] + rows + [RulesTable.border]
    return Data(lines.joined(separator: "\n").utf8)
}

final class HangGate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        continuation?.resume()
        continuation = nil
        lock.unlock()
    }
}

actor MockSwiftLintCLI: SwiftLintCLIProtocol {
    private let shouldFail: Bool
    private let mockRulesData: Data?
    private var mockLintOutput: Data = Data()
    private var shouldHang: Bool = false
    private let hangGate = HangGate()
    var lintCommandHandler: (@Sendable (URL?, URL) async throws -> Data)?

    init(shouldFail: Bool = false, mockRulesData: Data? = nil) {
        self.shouldFail = shouldFail
        self.mockRulesData = mockRulesData
    }

    func setMockLintOutput(_ data: Data) {
        mockLintOutput = data
    }

    func setShouldHang(_ value: Bool) {
        shouldHang = value
        if !value {
            hangGate.open()
        }
    }

    func setLintCommandHandler(_ handler: @escaping @Sendable (URL?, URL) async throws -> Data) {
        lintCommandHandler = handler
    }

    func detectSwiftLintPath() async throws -> URL {
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

    func executeRulesCommand() async throws -> Data {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        if let data = mockRulesData {
            return data
        }
        return makeRulesTableData(rows: [])
    }

    func executeRuleDetailCommand(ruleId: String) async throws -> Data {
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

    func generateDocsForRule(ruleId: String) async throws -> String {
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

    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
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

    func getVersion() async throws -> String {
        await Task.yield()
        if shouldFail {
            throw SwiftLintError.invalidVersion
        }
        return "0.50.0"
    }
}

actor RuleDetailsSwiftLintCLI: SwiftLintCLIProtocol {
    let docs: String
    let detail: String

    init(docs: String, detail: String) {
        self.docs = docs
        self.detail = detail
    }

    func detectSwiftLintPath() async throws -> URL {
        await Task.yield()
        throw SwiftLintError.notFound
    }

    func executeRulesCommand() async throws -> Data {
        await Task.yield()
        return Data()
    }

    func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        await Task.yield()
        return Data(detail.utf8)
    }

    func generateDocsForRule(ruleId: String) async throws -> String {
        await Task.yield()
        return docs
    }

    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        await Task.yield()
        return Data()
    }

    func getVersion() async throws -> String {
        await Task.yield()
        return "0.0.0"
    }
}

final class MockCacheManager: CacheManagerProtocol, @unchecked Sendable {
    var cachedRules: [Rule] = []
    var shouldFailLoad = false
    var shouldFailSave = false
    var cachedVersion: String?
    var cachedDocsDirectory: URL?

    func loadCachedRules() throws -> [Rule] {
        if shouldFailLoad {
            throw NSError(domain: "TestError", code: 1)
        }
        return cachedRules
    }

    func saveCachedRules(_ rules: [Rule]) throws {
        if shouldFailSave {
            throw NSError(domain: "TestError", code: 1)
        }
        cachedRules = rules
    }

    func clearCache() throws {
        cachedRules = []
    }

    func getCachedSwiftLintVersion() throws -> String? {
        cachedVersion
    }

    func saveSwiftLintVersion(_ version: String) throws {
        cachedVersion = version
    }

    func getCachedDocsDirectory() -> URL? {
        cachedDocsDirectory
    }

    func saveDocsDirectory(_ url: URL) throws {
        cachedDocsDirectory = url
    }

    func clearDocsCache() throws {
        cachedDocsDirectory = nil
    }
}
