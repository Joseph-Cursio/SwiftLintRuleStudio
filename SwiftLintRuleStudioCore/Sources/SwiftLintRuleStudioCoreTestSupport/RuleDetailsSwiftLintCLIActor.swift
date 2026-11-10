//
//  RuleDetailsSwiftLintCLIActor.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore

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

    public func executeRuleDetailCommand(ruleId _: String) async throws -> Data {
        await Task.yield()
        return Data(detail.utf8)
    }

    public func generateDocsForRule(ruleId _: String) async throws -> String {
        await Task.yield()
        return docs
    }

    public func executeLintCommand(configPath _: URL?, workspacePath _: URL) async throws -> Data {
        await Task.yield()
        return Data()
    }

    public func getVersion() async throws -> String {
        await Task.yield()
        return "0.0.0"
    }
}
