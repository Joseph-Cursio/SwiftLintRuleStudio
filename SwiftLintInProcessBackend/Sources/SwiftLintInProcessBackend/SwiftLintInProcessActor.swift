import Foundation
// Scoped imports: pull ONLY the seam symbols from Core. A broad import would make
// `Rule`/`RuleRegistry`/`Configuration` ambiguous, since Core declares its own.
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
        // SwiftLint lints synchronously and keeps every core busy. As a synchronous witness
        // for this async requirement, the lint ran on the caller's executor — the main actor
        // when the UI called in — and froze the app until it finished. A detached task runs
        // it on the cooperative pool instead, so the UI stays live and can show progress.
        try await Task.detached(priority: .userInitiated) {
            try Self.lint(configPath: configPath, workspacePath: workspacePath)
        }.value
    }

    /// Lints `workspacePath` the way `swiftlint lint` run in that directory would, except
    /// where SwiftLint's path-keyed config caches would make the result stale:
    ///
    /// - With `configPath` — the app's workspace analysis — that config applies alone, as
    ///   with `--config`. SwiftLint caches the root config merged with each nested config by
    ///   path, so files beneath a nested config would keep being linted against the root
    ///   config as it was at the first lint, hiding the app's own edits to `.swiftlint.yml`.
    /// - Without one — rule simulation, which lints a mirror at a new path for every rule —
    ///   the workspace's `.swiftlint.yml` and the nested configs beneath it apply, as they do
    ///   for the subprocess backend.
    static func lint(configPath: URL?, workspacePath: URL) throws -> Data {
        prepare()
        // SwiftLint looks for `.swiftlint.yml`, and stops its nested-config search, at the
        // working directory. The app's isn't the workspace, so override it for this lint.
        return try CurrentWorkingDirectory.$url.withValue(workspacePath) {
            let root = try InProcessConfiguration.root(configPath: configPath, workspacePath: workspacePath)
            let files = root.lintableFiles(
                inPath: workspacePath,
                forceExclude: false,
                excludeByPrefix: false
            )
            let appliesNestedConfigs = configPath == nil
            if appliesNestedConfigs {
                try InProcessConfiguration.checkNestedConfigs(
                    for: files.compactMap(\.path),
                    workspacePath: workspacePath
                )
            }
            let storage = RuleStorage()
            let violations = files
                .map { file in
                    Linter(file: file, configuration: appliesNestedConfigs ? root.configuration(for: file) : root)
                }
                .map { $0.collect(into: storage) }
                .flatMap { $0.styleViolations(using: storage) }
            return Data(jsonReport(for: violations).utf8)
        }
    }

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
