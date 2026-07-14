import Foundation
import SwiftLintFramework
// Scoped imports: pull ONLY the seam symbols from Core. A broad import would make
// `Rule`/`RuleRegistry`/`Configuration` ambiguous, since Core declares its own.
import protocol SwiftLintRuleStudioCore.SwiftLintCLIProtocol
import enum SwiftLintRuleStudioCore.SwiftLintError

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
public actor SwiftLintInProcessActor: SwiftLintCLIProtocol {

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

    public func detectSwiftLintPath() async throws -> URL {
        // No external binary — SwiftLint is linked in-process.
        URL(fileURLWithPath: "in-process/SwiftLintFramework")
    }

    public func getVersion() async throws -> String {
        Self.prepare()
        return Version.current.value
    }

    public func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        Self.prepare()
        let configuration = Configuration(configurationFiles: configPath.map { [$0] } ?? [])
        let files = configuration.lintableFiles(
            inPath: workspacePath,
            forceExclude: false,
            excludeByPrefix: false
        )
        let storage = RuleStorage()
        let violations = files
            .map { Linter(file: $0, configuration: configuration) }
            .map { $0.collect(into: storage) }
            .flatMap { $0.styleViolations(using: storage) }
        return Data(Self.jsonReport(for: violations).utf8)
    }

    public func executeRulesCommand() async throws -> Data {
        Self.prepare()
        return Data(Self.rulesTable().utf8)
    }

    public func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        Self.prepare()
        guard let description = Self.ruleDescription(forID: ruleId) else {
            throw SwiftLintError.executionFailed(message: "Unknown rule: \(ruleId)")
        }
        return Data(Self.ruleDetailText(for: description).utf8)
    }

    public func generateDocsForRule(ruleId: String) async throws -> String {
        Self.prepare()
        guard let description = Self.ruleDescription(forID: ruleId) else {
            throw SwiftLintError.executionFailed(message: "Unknown rule: \(ruleId)")
        }
        return Self.markdownDoc(for: description)
    }
}
