//
//  UnconfiguredSwiftLintBackend.swift
//  SwiftLintRuleStudio
//
//  A no-op `SwiftLintCLIProtocol` backend used ONLY as a compile-time default for
//  SwiftUI environment values and previews in the shared UI. Real app targets
//  inject a concrete backend at launch — the subprocess `SwiftLintCLIActor` for
//  the (non-sandboxed) Studio target, the in-process actor for the sandboxed
//  Explorer target — so this is never exercised at runtime. It exists so the
//  shared UI can compile in either target without naming a concrete backend or
//  linking a backend module.
//
//  Methods return benign empties (no rules, no violations) rather than throwing,
//  so previews render clean empty states instead of error states.
//

import Foundation

public nonisolated struct UnconfiguredSwiftLintBackend: SwiftLintCLIProtocol {
    public init() {}

    public func detectSwiftLintPath() async throws -> URL {
        throw SwiftLintError.notFound
    }

    public func executeRulesCommand() async throws -> Data {
        Data()
    }

    public func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        Data()
    }

    public func generateDocsForRule(ruleId: String) async throws -> String {
        ""
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        Data("[]".utf8)
    }

    public func getVersion() async throws -> String {
        ""
    }
}
