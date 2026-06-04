//
//  SwiftLintCLIActor.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import LintStudioCore

/// Closure type for running SwiftLint commands. Receives the command name and
/// arguments, returns `(stdout, stderr, exitCode)`. Injected in tests to return
/// canned fixtures (including a chosen exit code, which drives the exit-code
/// policy) without launching a process.
public typealias SwiftLintCommandRunner = @Sendable (String, [String]) async throws -> (Data, Data, Int32)
/// Closure type for checking file existence
public typealias SwiftLintFileExists = @Sendable (String) async -> Bool

/// Protocol for SwiftLint CLI operations
public protocol SwiftLintCLIProtocol: Sendable {
    func detectSwiftLintPath() async throws -> URL
    func executeRulesCommand() async throws -> Data
    func executeRuleDetailCommand(ruleId: String) async throws -> Data
    func generateDocsForRule(ruleId: String) async throws -> String
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data
    func getVersion() async throws -> String
}

public enum SwiftLintError: LocalizedError, Sendable {
    case notFound
    case invalidVersion
    case executionFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return """
            SwiftLint not found. Please install SwiftLint using one of these methods:

            • Homebrew: brew install swiftlint
            • Mint: mint install realm/SwiftLint
            • CocoaPods: Add to your Podfile
            • Direct download: https://github.com/realm/SwiftLint/releases

            After installing, restart SwiftLint Rule Studio.
            """
        case .invalidVersion:
            return "Could not determine SwiftLint version."
        case .executionFailed(let message):
            return "SwiftLint execution failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Install SwiftLint using Homebrew: brew install swiftlint"
        default:
            return nil
        }
    }
}

/// Service for executing SwiftLint CLI commands.
///
/// A thin wrapper over `LintStudioCore.CLIToolActor`: the shared actor owns the
/// path-detection / run / capture / timeout mechanics and the SwiftLint-modeled
/// exit-code policy (`successExitCodes` `[0, 2]` — `0` clean, `2` ran and found
/// serious violations; `127` → not found; anything else → execution failure).
/// What stays here is the SwiftLint-specific argument building, documentation
/// generation/caching, version parsing, and the `SwiftLintError` surface that
/// existing callers and tests expect.
public actor SwiftLintCLIActor: SwiftLintCLIProtocol {
    public let cacheManager: CacheManager
    private let tool: CLIToolActor
    private let fileExists: SwiftLintFileExists

    public init(
        cacheManager: CacheManagerProtocol? = nil,
        commandRunner: SwiftLintCommandRunner? = nil,
        fileExists: SwiftLintFileExists? = nil,
        timeoutSeconds: UInt64 = 300
    ) {
        // Store as concrete CacheManager (a Sendable value type) to avoid
        // protocol-existential isolation issues crossing the actor boundary.
        if let provided = cacheManager as? CacheManager {
            self.cacheManager = provided
        } else {
            self.cacheManager = CacheManager()
        }
        self.fileExists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }

        // Bridge the SwiftLint-local runner seam to CLIToolActor's. The tool
        // name is fixed to "swiftlint", so it is supplied here for callers
        // (and recorders) that inspect the command name.
        var bridgedRunner: CLIToolCommandRunner?
        if let commandRunner {
            bridgedRunner = { arguments, _ in
                try await commandRunner("swiftlint", arguments)
            }
        }

        self.tool = CLIToolActor(
            toolName: "swiftlint",
            installMessage: SwiftLintError.notFound.errorDescription,
            timeoutSeconds: timeoutSeconds,
            allowShellFallback: true,
            successExitCodes: [0, 2],
            fileExists: fileExists,
            commandRunner: bridgedRunner
        )
    }

    // MARK: - SwiftLintCLIProtocol

    public func detectSwiftLintPath() async throws -> URL {
        try await mapping { try await tool.detectPath() }
    }

    public func executeRulesCommand() async throws -> Data {
        try await runSwiftLint(arguments: ["rules"])
    }

    public func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        try await runSwiftLint(arguments: ["rules", ruleId])
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        let arguments = await Self.buildLintArguments(
            configPath: configPath,
            workspacePath: workspacePath,
            fileExists: fileExists
        )
        return try await runSwiftLint(arguments: arguments)
    }

    public func getVersion() async throws -> String {
        let result = try await mapping { try await tool.run(arguments: ["version"]) }
        // Decode the raw bytes directly (not `stdoutString`, which substitutes an
        // empty string for undecodable data) so non-UTF-8 output still surfaces
        // as `.invalidVersion`.
        guard let version = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SwiftLintError.invalidVersion
        }
        return version
    }

    // MARK: - Execution

    /// Runs `swiftlint <arguments>` and returns stdout. Used by the rules,
    /// rule-detail, lint, and documentation paths.
    func runSwiftLint(arguments: [String]) async throws -> Data {
        try await mapping { try await tool.run(arguments: arguments).stdout }
    }

    /// Translates `CLIToolError` into the `SwiftLintError` surface that callers
    /// (and existing tests) expect.
    private func mapping<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as CLIToolError {
            switch error {
            case .notFound:
                throw SwiftLintError.notFound
            case .timedOut(_, let seconds):
                throw SwiftLintError.executionFailed(
                    message: "SwiftLint command timed out after \(seconds) seconds."
                )
            case .executionFailed(let message):
                throw SwiftLintError.executionFailed(message: message)
            }
        }
    }
}
