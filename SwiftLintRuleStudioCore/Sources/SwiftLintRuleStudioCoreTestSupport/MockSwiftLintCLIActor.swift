//
//  MockSwiftLintCLIActor.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore

public actor MockSwiftLintCLIActor: SwiftLintCLIProtocol {
    private let shouldFail: Bool
    private let mockRulesData: Data?
    private var mockLintOutput = Data()
    private var shouldHang: Bool = false
    private let hangGate = HangGate()
    public var lintCommandHandler: (@Sendable (URL?, URL) async throws -> Data)?
    public var ruleDetailCommandHandler: (@Sendable (String) async throws -> Data)?
    public var generateDocsHandler: (@Sendable (String) async throws -> String)?

    public init(shouldFail: Bool = false, mockRulesData: Data? = nil) {
        self.shouldFail = shouldFail
        self.mockRulesData = mockRulesData
    }

    public func setRuleDetailCommandHandler(
        _ handler: @escaping @Sendable (String) async throws -> Data
    ) {
        ruleDetailCommandHandler = handler
    }

    public func setGenerateDocsHandler(
        _ handler: @escaping @Sendable (String) async throws -> String
    ) {
        generateDocsHandler = handler
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
            "/usr/bin/swiftlint",
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
        if let handler = ruleDetailCommandHandler {
            return try await handler(ruleId)
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
        if let handler = generateDocsHandler {
            return try await handler(ruleId)
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
