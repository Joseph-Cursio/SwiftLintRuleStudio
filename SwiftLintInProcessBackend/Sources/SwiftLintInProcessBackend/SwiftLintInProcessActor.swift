import Foundation
// Scoped imports: pull ONLY the seam symbols from Core. A broad import would make
// `Rule`/`RuleRegistry`/`Configuration` ambiguous, since Core declares its own.
import struct SwiftLintCLISeam.LintProgress
import typealias SwiftLintCLISeam.LintProgressHandler
import protocol SwiftLintCLISeam.SwiftLintCLIProtocol
import enum SwiftLintCLISeam.SwiftLintError
import SwiftLintFramework

/// In-process SwiftLint backend for the sandboxed (Mac App Store) app target.
///
/// Conforms to the same `SwiftLintCLIProtocol` seam as the subprocess
/// `SwiftLintCLIActor`, but links SwiftLintFramework and lints in-process — no
/// external `swiftlint` binary, no `xcrun`, no sourcekitd.
///
/// Why the env vars (see the sandbox spike): SwiftLint eagerly probes SourceKit
/// for the Swift compiler version on the first lint (`SwiftVersion.current`),
/// which under the App Sandbox shells out to `xcrun` (blocked) and then fails to
/// load `sourcekitd` from outside the app container. `SWIFTLINT_DISABLE_SOURCEKIT`
/// makes SwiftLint skip that probe and gracefully skip the ~12 SourceKit rules;
/// `SWIFTLINT_SWIFT_VERSION` supplies the version so rule gating stays correct.
/// A GUI `.app` doesn't inherit shell env, so these are set via `setenv` at
/// startup, before any SwiftLintFramework symbol is touched.
/// Declared as a `final class` rather than an `actor`, deliberately. It has no mutable
/// stored state — only a `static let` and function-local values — so there is nothing for
/// actor isolation to serialize, and the isolation was decorative. It also has to conform to
/// `SwiftLintCLIProtocol`, which is `nonisolated` so that every backend and test double can
/// implement it; an actor conforming to that seam is accepted by one Swift version and
/// rejected by another, and this type gains nothing by sitting on that fault line.
public final class SwiftLintInProcessActor: SwiftLintCLIProtocol {

    /// The Swift version this app is built against. SwiftLint uses it to gate
    /// version-specific rules. Keep in sync with the toolchain on version bumps.
    static let pinnedSwiftVersion = "6.3.3"

    /// Runs exactly once (thread-safe lazy static), before any SwiftLintFramework
    /// symbol is touched. Sets the sandbox-safety env vars, then registers the
    /// built-in rule set — the CLI's one-shot `registerAllRulesOnce()` is
    /// `package`-scoped, so we use the public `register(rules:)` + `builtInRules`.
    private static let bootstrap: Void = {
        setenv("SWIFTLINT_DISABLE_SOURCEKIT", "1", 1)
        setenv("SWIFTLINT_SWIFT_VERSION", pinnedSwiftVersion, 1)
        RuleRegistry.shared.register(rules: builtInRules)
    }()

    /// Force the one-time bootstrap now. The Explorer app should call this at
    /// launch so the env vars are set well before the first lint; the actor also
    /// triggers it defensively on every entry point.
    public static func prepare() {
        _ = bootstrap
    }

    public init() {}

    // MARK: - SwiftLintCLIProtocol

    public func detectSwiftLintPath() throws -> URL {
        // No external binary — SwiftLint is linked in-process.
        URL(fileURLWithPath: "in-process/SwiftLintFramework")
    }

    public func getVersion() throws -> String {
        Self.prepare()
        return Version.current.value
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        try await executeLintCommand(configPath: configPath, workspacePath: workspacePath) { _ in }
    }

    /// Lints the workspace as SwiftLint run in it does — its `.swiftlint.yml` and the nested
    /// configs beneath it — as the subprocess backend's `.effective` mode does. `configPath`
    /// isn't forced: the app names only the workspace's own `.swiftlint.yml`, which SwiftLint
    /// finds anyway, and forcing it would turn the nested configs off.
    public func executeLintCommand(
        configPath _: URL?,
        workspacePath: URL,
        progress: @escaping LintProgressHandler
    ) async throws -> Data {
        // SwiftLint lints synchronously and keeps every core busy. As a synchronous witness
        // for this async requirement, the lint ran on the caller's executor — the main actor
        // when the UI called in — and froze the app until it finished. A detached task runs
        // it on the cooperative pool instead, so the UI stays live and can show progress.
        try await Task.detached(priority: .userInitiated) {
            try Self.lint(configPath: nil, workspacePath: workspacePath, progress: progress)
        }.value
    }

    /// Lints a rule simulation's mirror, as ``executeLintCommand(configPath:workspacePath:)``
    /// does with no config path — except that a cancelled caller stops waiting at once. The lint
    /// can't be interrupted, so it runs on and its result is discarded; see ``InFlightLints``.
    public func executeSimulationLintCommand(workspacePath: URL) async throws -> Data {
        try await Self.simulationLints.run(at: workspacePath) {
            try Self.lint(configPath: nil, workspacePath: workspacePath)
        }
    }

    public func waitForAbandonedLints(at workspacePath: URL) async {
        await Self.simulationLints.waitForLints(at: workspacePath)
    }

    /// Shared by every instance: a lint outlives the backend that started it.
    private static let simulationLints = InFlightLints()

    /// Lints `workspacePath` the way `swiftlint lint` run in that directory would:
    ///
    /// - Without `configPath` — the workspace analysis and rule simulation — the workspace's
    ///   `.swiftlint.yml` and the nested configs beneath it apply, as in the subprocess
    ///   backend's `.effective` mode.
    /// - With one, that config applies alone, as with `--config`: the subprocess backend's
    ///   `.rootConfigOnly` mode, kept for reasoning about one config by itself. Nothing in the
    ///   app lints this way yet.
    ///
    /// `progress` hears once the files are found, then again as each one is linted.
    static func lint(
        configPath: URL?,
        workspacePath: URL,
        progress: LintProgressHandler = { _ in }
    ) throws -> Data {
        prepare()
        // SwiftLint looks for `.swiftlint.yml`, and stops its nested-config search, at the
        // working directory. The app's isn't the workspace, so override it for this lint.
        return try CurrentWorkingDirectory.$url.withValue(workspacePath) {
            let root = try withConfigurationCaches {
                try InProcessConfiguration.root(configPath: configPath, workspacePath: workspacePath)
            }
            // A link SwiftLint's file walk follows round for ever overflows the stack, and
            // in-process that ends the app; the `swiftlint` process just dies.
            try SymlinkLoopCheck.check(root, workspacePath: workspacePath)
            let files = root.lintableFiles(
                inPath: workspacePath,
                forceExclude: false,
                excludeByPrefix: false
            )
            // `swiftlint lint` fails when there is nothing to lint, unless the config sets
            // `allow_zero_lintable_files` (Configuration+CommandLine's `groupFiles`). This
            // returned no violations instead, so a folder nobody linted read as clean — and in
            // a rule simulation, every rule read as safe to enable. Done for every lint, not
            // just simulations, so both editions say the same thing about the same folder.
            if files.isEmpty, !root.allowZeroLintableFiles {
                throw SwiftLintError.executionFailed(
                    message: "No lintable files found at paths: '\(workspacePath.path)'"
                )
            }
            let configurations: [Configuration]
            if configPath == nil {
                try InProcessConfiguration.checkNestedConfigs(
                    for: files.compactMap(\.path),
                    workspacePath: workspacePath
                )
                configurations = withConfigurationCaches { files.map { root.configuration(for: $0) } }
            } else {
                configurations = files.map { _ in root }
            }
            progress(LintProgress(filesLinted: 0, totalFiles: files.count))
            let storage = RuleStorage()
            // Every file is collected before any is linted: collecting rules need what the
            // whole workspace holds before they can judge one file.
            let linters = zip(files, configurations)
                .map { Linter(file: $0, configuration: $1) }
                .map { $0.collect(into: storage) }
            var violations: [StyleViolation] = []
            for (index, linter) in linters.enumerated() {
                violations += linter.styleViolations(using: storage)
                progress(LintProgress(filesLinted: index + 1, totalFiles: linters.count))
            }
            return Data(jsonReport(for: violations).utf8)
        }
    }

    /// SwiftLint keeps every config it loads from a file, and its answer for every folder it
    /// searches for a nested config, in caches shared by the whole process and keyed by path,
    /// never by contents. `swiftlint` exits after one lint. Here, a lint would see a config as
    /// it was at the first lint of that folder, read what a lint of the same folder still
    /// running put there, and leave every simulated rule's entries until the app quits.
    ///
    /// So a lint makes the calls that use those caches — building its root config, and finding
    /// each file's — in `body`, with the caches to itself: empty when it starts, as in a fresh
    /// process, and emptied when it's done. Its file walks run between, not holding them up.
    private static func withConfigurationCaches<T>(_ body: () throws -> T) rethrows -> T {
        try configurationCaches.withLock {
            Configuration.resetCache()
            defer { Configuration.resetCache() }
            return try body()
        }
    }

    private static let configurationCaches = NSLock()

    public func executeRulesCommand() throws -> Data {
        Self.prepare()
        return Data(Self.rulesTable().utf8)
    }

    public func executeRuleDetailCommand(ruleId: String) throws -> Data {
        Self.prepare()
        guard let description = Self.ruleDescription(forID: ruleId) else {
            throw SwiftLintError.executionFailed(message: "Unknown rule: \(ruleId)")
        }
        return Data(Self.ruleDetailText(for: description).utf8)
    }

    public func generateDocsForRule(ruleId: String) throws -> String {
        Self.prepare()
        guard let description = Self.ruleDescription(forID: ruleId) else {
            throw SwiftLintError.executionFailed(message: "Unknown rule: \(ruleId)")
        }
        return Self.markdownDoc(for: description)
    }
}
