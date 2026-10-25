//  The SwiftLint CLI seam.
//
//  This file lives in its own target for one reason: the target does **not** set
//  `.defaultIsolation(MainActor.self)`. In Core, which does, every declaration is
//  MainActor-isolated unless it opts out, and these had to carry `nonisolated` to
//  undo a default they never wanted. That opt-out is what put the seam on a
//  compiler fault line — an actor conforming to a `nonisolated` protocol is
//  accepted by one Swift version and rejected by another.
//
//  With no isolation default to undo, there is no keyword, and nothing for two
//  compilers to disagree about. A seam implemented by every backend and every test
//  double should not inherit an app's isolation policy in the first place.

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

/// Output of a SwiftLint command: standard output, standard error, and the
/// process exit code (which drives the exit-code policy).
public struct SwiftLintCommandOutput: Sendable {
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

    /// Lints a rule simulation's throwaway mirror at `workspacePath`, discovering its
    /// configs from there as `executeLintCommand(configPath: nil, workspacePath:)` does.
    ///
    /// Apart from analysis because a simulation lints a fresh path for every rule: a cache
    /// written for it is never read again, and an audit cancelled midway should stop the lint
    /// it is waiting on rather than see it through.
    func executeSimulationLintCommand(workspacePath: URL) async throws -> Data

    /// Returns once no lint the backend stopped waiting on — because its caller was cancelled —
    /// is still reading `workspacePath`, so the mirror there can be removed safely.
    func waitForAbandonedLints(at workspacePath: URL) async
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

public extension SwiftLintCLIProtocol {
    /// A backend with nothing to set apart for a simulation lints it like analysis.
    func executeSimulationLintCommand(workspacePath: URL) async throws -> Data {
        try await executeLintCommand(configPath: nil, workspacePath: workspacePath)
    }

    /// A backend that always sees its lints through has none to wait for.
    func waitForAbandonedLints(at _: URL) {}
}
