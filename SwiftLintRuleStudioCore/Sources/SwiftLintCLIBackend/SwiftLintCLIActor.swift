//
//  SwiftLintCLIActor.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import LintStudioCore
import SwiftLintCLISeam
import SwiftLintRuleStudioCore

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
    public let cacheManager: any CacheManagerProtocol
    private let tool: CLIToolActor
    private let fileExists: SwiftLintFileExists
    private let timeoutSeconds: UInt64
    /// Whether a test supplied the command runner, which a simulation lint must go through too.
    private let runsInjectedCommands: Bool
    /// Directory that holds the generated `rule_docs/<version>/` subtree. Injected
    /// in tests to a temp directory so doc generation doesn't write into the real
    /// Application Support folder; defaults to `.../SwiftLintRuleStudio` there.
    let docsRootDirectory: URL

    public init(
        cacheManager: CacheManagerProtocol? = nil,
        commandRunner: SwiftLintCommandRunner? = nil,
        fileExists: SwiftLintFileExists? = nil,
        docsRootDirectory: URL? = nil,
        timeoutSeconds: UInt64 = 300
    ) {
        // Store the injected cache through its protocol. `CacheManagerProtocol` is
        // `Sendable`, so the existential crosses the actor boundary safely — and an
        // injected test double (e.g. `MockCacheManager`) is honored rather than being
        // discarded in favor of a fresh `CacheManager`.
        self.cacheManager = cacheManager ?? CacheManager()
        self.fileExists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        self.timeoutSeconds = timeoutSeconds
        self.runsInjectedCommands = commandRunner != nil

        // Default docs root to the real Application Support location (temp dir as a
        // last resort). Tests inject a temp directory to stay isolated.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.docsRootDirectory = docsRootDirectory
            ?? appSupport.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)

        // Bridge the SwiftLint-local runner seam to CLIToolActor's. The tool
        // name is fixed to "swiftlint", so it is supplied here for callers
        // (and recorders) that inspect the command name.
        var bridgedRunner: CLIToolCommandRunner?
        if let commandRunner {
            bridgedRunner = { arguments, _ in
                let output = try await commandRunner("swiftlint", arguments)
                return (output.stdout, output.stderr, output.exitCode)
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

    /// Lints the workspace in `.effective` mode — SwiftLint discovers the root
    /// config *and* nested `.swiftlint.yml` files itself, matching what the
    /// developer and CI see. `configPath` is retained for the protocol surface
    /// and the forthcoming "This config only" (`.rootConfigOnly`) preview; it is
    /// intentionally not forced via `--config` here, which would disable nested
    /// resolution and over-report violations in folders a nested config relaxes.
    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        let arguments = await Self.buildLintArguments(
            configPath: configPath,
            workspacePath: workspacePath,
            mode: .effective,
            fileExists: fileExists
        )
        // Launch in the workspace directory so SwiftLint discovers its
        // `.swiftlint.yml` (and the `excluded:` paths within it) from the cwd, as
        // it does on the command line. Without this the app inherits cwd `/`,
        // SwiftLint finds no config, and lints excluded trees (e.g. SwiftSyntax
        // checkouts under .build) — thousands of phantom violations, far slower.
        return try await runLint(arguments: arguments, workingDirectory: workspacePath)
    }

    /// Lints a rule simulation's mirror with no cache, in a process a cancelled caller
    /// terminates — so an audit cancelled midway stops the lint it was waiting on.
    public func executeSimulationLintCommand(workspacePath: URL) async throws -> Data {
        try await runLint(
            arguments: Self.buildSimulationLintArguments(workspacePath: workspacePath),
            workingDirectory: workspacePath
        )
    }

    /// Runs a lint in `workingDirectory` with `PWD` naming it — a GUI app has no `PWD`, and
    /// SwiftLint expands `${PWD}` in a config from it — in a process a cancelled caller
    /// terminates.
    private func runLint(arguments: [String], workingDirectory: URL) async throws -> Data {
        guard !runsInjectedCommands else {
            return try await runSwiftLint(arguments: arguments, workingDirectory: workingDirectory)
        }
        if let binary = try? await tool.detectPath() {
            return try await CancellableSwiftLintRun.run(
                binary: binary,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            )
        }
        // Not where it's usually installed: found through the shell's PATH, as `CLIToolActor`'s
        // fallback does — a swiftlint from Mint, mise, asdf or Nix — and cancellable all the same.
        return try await CancellableSwiftLintRun.run(
            binary: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", CLIToolActor.buildShellCommand(command: "swiftlint", arguments: arguments)],
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        )
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
    func runSwiftLint(arguments: [String], workingDirectory: URL? = nil) async throws -> Data {
        try await mapping { try await tool.run(arguments: arguments, workingDirectory: workingDirectory).stdout }
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
