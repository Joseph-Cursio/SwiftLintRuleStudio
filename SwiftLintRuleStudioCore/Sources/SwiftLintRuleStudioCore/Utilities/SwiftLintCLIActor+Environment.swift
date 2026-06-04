import Foundation

/// How SwiftLint resolves configuration when linting a workspace.
///
/// SwiftLint supports *nested* configurations: a `.swiftlint.yml` in a
/// subdirectory is merged with its ancestors and applies to files beneath it
/// (the classic case being `Tests/.swiftlint.yml` relaxing `force_try` /
/// `force_unwrapping`). Passing `--config` **disables** that nested resolution,
/// so forcing it makes the GUI disagree with what the developer and CI actually
/// see — over-reporting violations in any folder a nested config relaxes.
public enum LintExecutionMode: Sendable {
    /// Run SwiftLint the way the developer and CI do: let it discover the root
    /// `.swiftlint.yml` *and* any nested configs from the linted paths. No
    /// `--config` is passed. This matches reality and is the default.
    case effective

    /// Force the single root config via `--config`, disabling nested
    /// resolution. Use only for reasoning about one config in isolation
    /// (the "This config only" preview), never for whole-project analysis.
    case rootConfigOnly
}

public extension SwiftLintCLIActor {
    /// Builds the argument array for `swiftlint lint --reporter json`.
    ///
    /// In `.effective` mode (the default) no `--config` flag is added, so
    /// SwiftLint applies nested `.swiftlint.yml` files exactly as it does on the
    /// command line / in CI. In `.rootConfigOnly` mode the root config is forced
    /// via `--config`, which disables nested resolution.
    nonisolated static func buildLintArguments(
        configPath: URL?,
        workspacePath: URL,
        mode: LintExecutionMode = .effective,
        fileExists: @escaping SwiftLintFileExists
    ) async -> [String] {
        var arguments = ["lint", "--reporter", "json"]
        if case .rootConfigOnly = mode,
           let configPath = configPath,
           await fileExists(configPath.path) {
            arguments.append(contentsOf: ["--config", configPath.path])
        }
        arguments.append(workspacePath.path)
        return arguments
    }
}
