//
//  SwiftLintCLIProtocol.swift
//  SwiftLintRuleStudio
//
//  The backend seam: the protocol and value types that decouple the app from
//  *how* SwiftLint is executed. Concrete backends (subprocess `SwiftLintCLIActor`,
//  or a future in-process implementation) live in their own modules and conform
//  to `SwiftLintCLIProtocol`. Core depends only on this seam, never on a backend.
//

import Foundation
import LintStudioCore

/// Output of a SwiftLint command: standard output, standard error, and the
/// process exit code (which drives the exit-code policy).
public nonisolated struct SwiftLintCommandOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    nonisolated public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Closure type for running SwiftLint commands. Receives the command name and
/// arguments, returns the command output. Injected in tests to return canned
/// fixtures (including a chosen exit code, which drives the exit-code policy)
/// without launching a process.
public typealias SwiftLintCommandRunner = @Sendable (String, [String]) async throws -> SwiftLintCommandOutput
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

public nonisolated enum SwiftLintError: LocalizedError, Sendable {
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
