import Foundation
import SwiftLintFramework
import Yams

enum InProcessConfigurationError: LocalizedError {
    case unreadable(file: URL, reason: String)
    case versionMismatch(file: URL, pinned: String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(file, reason):
            "Couldn't read \(file.path): \(reason)"
        case let .versionMismatch(file, pinned):
            "\(file.path) requires SwiftLint \(pinned), but SwiftLint \(Version.current.value) is built in."
        }
    }
}

/// Builds the SwiftLint `Configuration` for an in-process lint, matching what a fresh
/// `swiftlint` process run in the workspace would use.
///
/// Three things differ from the subprocess backend:
/// - The app's working directory isn't the workspace, so SwiftLint can't find
///   `.swiftlint.yml` (or stop its nested-config search) on its own. The lint runs under
///   SwiftLint's task-local working-directory override instead of the process-wide one.
/// - There's no fresh process per lint. SwiftLint caches every configuration it loads from
///   a file under a key made of the working directory and the file's *path*, never its
///   contents, and offers no public way to clear that cache. A config edited on disk
///   would keep its first settings. So the root config is read from disk on every lint
///   and built from its contents.
/// - A process that ends is the app. SwiftLint ends the process for a config whose
///   `swiftlint_version` doesn't match, and for an invalid config it loads from a file —
///   a nested config, or one in a `parent_config`/`child_config` chain. Every config the
///   lint will load is checked here first, so those become errors instead.
///
/// Nested configs, and configs that use `parent_config`/`child_config`, still go through
/// SwiftLint's path-keyed caches. Rule simulation lints a mirror that moves to a new path
/// for every rule, so it never meets a stale entry.
enum InProcessConfiguration {
    /// The root configuration for a lint of `workspacePath`.
    ///
    /// - `configPath` given: that file alone, like `swiftlint --config`. The caller should
    ///   not apply nested configs.
    /// - `configPath` nil: the workspace's own `.swiftlint.yml`, or SwiftLint's defaults
    ///   when there is none. Nested configs apply through `configuration(for:)`, after
    ///   ``checkNestedConfigs(for:workspacePath:)``. Call this with `URL.cwd` overridden to
    ///   `workspacePath`, which is where SwiftLint stops its nested-config search.
    static func root(configPath: URL?, workspacePath: URL) throws -> Configuration {
        let file = configPath ?? workspacePath.appendingPathComponent(Configuration.defaultFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return try Configuration(dict: [:], location: workspacePath)
        }

        let dict = try checkedDictionary(at: file)
        let configuration = try checkedConfiguration(dict, at: file)
        guard dict.referencesOtherConfigs else { return configuration }

        // Only SwiftLint's file loader follows parent/child references. Check the chain
        // first; if it still fails to load, fall back to the defaults with a printed warning,
        // as the CLI does for a config it discovers, rather than ending the app.
        var visited: Set<URL> = [file.standardizedFileURL]
        try checkReferencedConfigs(of: dict, at: file, visited: &visited)
        return Configuration(configurationFiles: configPath.map { [$0] } ?? [], useDefaultConfigOnFailure: true)
    }

    /// Checks the nested config SwiftLint will load for each of `files`: the nearest
    /// `.swiftlint.yml` between the file and the workspace root, exclusive. SwiftLint loads
    /// these in a way that ends the process on any error.
    static func checkNestedConfigs(for files: [URL], workspacePath: URL) throws {
        let rootComponents = workspacePath.resolvingSymlinksInPath().pathComponents
        var checked: Set<URL> = []
        let directories = Set(files.map { $0.deletingLastPathComponent().resolvingSymlinksInPath() })
        for directory in directories {
            var current = directory
            while current.pathComponents.count > rootComponents.count,
                  current.pathComponents.starts(with: rootComponents) {
                let candidate = current.appendingPathComponent(Configuration.defaultFileName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    if checked.insert(candidate).inserted {
                        _ = try checkedConfiguration(checkedDictionary(at: candidate), at: candidate)
                    }
                    break
                }
                current = current.deletingLastPathComponent()
            }
        }
    }

    /// Parses YAML the way SwiftLint's own (internal) `YamlParser` does, including
    /// `${VARIABLE}` expansion from the environment.
    static func parse(
        _ yaml: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: Any] {
        var scalars = Constructor.defaultScalarMap
        scalars[.str] = { $0.string.expandingEnvVars(env: env) }
        scalars[.bool] = {
            switch $0.string.expandingEnvVars(env: env).lowercased() {
            case "true": true
            case "false": false
            default: nil
            }
        }
        scalars[.int] = { Int($0.string.expandingEnvVars(env: env)) }
        scalars[.float] = { Double($0.string.expandingEnvVars(env: env)) }
        return try Yams.load(yaml: yaml, .default, Constructor(scalars)) as? [String: Any] ?? [:]
    }

    // MARK: - Checks

    /// The parsed contents of `file`, which must pin no SwiftLint version but the built-in
    /// one: SwiftLint calls `exit` for any other.
    private static func checkedDictionary(at file: URL) throws -> [String: Any] {
        let dict: [String: Any]
        do {
            dict = try parse(String(contentsOf: file, encoding: .utf8))
        } catch {
            throw InProcessConfigurationError.unreadable(file: file, reason: String(describing: error))
        }
        if let pinned = dict["swiftlint_version"].map({ ($0 as? String) ?? String(describing: $0) }),
           pinned != Version.current.value {
            throw InProcessConfigurationError.versionMismatch(file: file, pinned: pinned)
        }
        return dict
    }

    private static func checkedConfiguration(_ dict: [String: Any], at file: URL) throws -> Configuration {
        do {
            return try Configuration(dict: dict, location: file.deletingLastPathComponent())
        } catch {
            throw InProcessConfigurationError.unreadable(file: file, reason: String(describing: error))
        }
    }

    /// Checks the local configs `dict` names under `parent_config`/`child_config`, and
    /// theirs in turn. Remote ones are left to SwiftLint.
    private static func checkReferencedConfigs(
        of dict: [String: Any],
        at file: URL,
        visited: inout Set<URL>
    ) throws {
        for key in ["parent_config", "child_config"] {
            guard let reference = dict[key] as? String, !reference.hasPrefix("http") else { continue }
            let referenced = URL(fileURLWithPath: reference, relativeTo: file.deletingLastPathComponent())
                .standardizedFileURL
            guard visited.insert(referenced).inserted,
                  FileManager.default.fileExists(atPath: referenced.path) else { continue }
            let referencedDict = try checkedDictionary(at: referenced)
            _ = try checkedConfiguration(referencedDict, at: referenced)
            try checkReferencedConfigs(of: referencedDict, at: referenced, visited: &visited)
        }
    }
}

private extension [String: Any] {
    var referencesOtherConfigs: Bool {
        self["parent_config"] != nil || self["child_config"] != nil
    }
}

private extension String {
    func expandingEnvVars(env: [String: String]) -> String {
        guard contains("${") else { return self }
        return env.reduce(into: self) { result, variable in
            result = result.replacingOccurrences(of: "${\(variable.key)}", with: variable.value)
        }
    }
}
