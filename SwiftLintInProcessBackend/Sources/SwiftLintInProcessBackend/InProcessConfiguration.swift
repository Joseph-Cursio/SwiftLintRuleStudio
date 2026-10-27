import Foundation
import SwiftLintFramework
import Yams

enum InProcessConfigurationError: LocalizedError {
    case unreadable(file: URL, reason: String)
    case versionMismatch(file: URL, pinned: String)
    case usesWorkingDirectory(file: URL)
    case customRulesNeedSourceKit

    var errorDescription: String? {
        switch self {
        case .customRulesNeedSourceKit:
            "This workspace's custom rules are all set to `execution_mode: swiftsyntax`, but SwiftLint "
                + "\(Version.current.value) still asks SourceKit about each file when it runs them, and the "
                + "built-in SwiftLint can't load SourceKit. Custom rules set to `execution_mode: sourcekit` "
                + "are skipped instead."
        case let .usesWorkingDirectory(file):
            "\(file.path) uses ${PWD}, which SwiftLint fills in with the folder it runs in. The built-in "
                + "SwiftLint runs inside the app, whose working directory is one for every lint, so it can't."
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
///   contents. The lint clears those caches before and after it runs
///   (`SwiftLintInProcessActor.lint`). The root config is still read from disk and built
///   from its contents where it can be, so that it is checked first.
/// - A process that ends is the app. SwiftLint ends the process for a config whose
///   `swiftlint_version` doesn't match, and for an invalid config it loads from a file —
///   a nested config, or one in a `parent_config`/`child_config` chain. Every config the
///   lint will load is checked here first, so those become errors instead.
enum InProcessConfiguration {
    /// The root configuration for a lint of `workspacePath`, and its file graph: the config
    /// files SwiftLint's loader built it from, spelled as that loader spells them. SwiftLint's
    /// nested-config search passes over these. They are the root config and its
    /// `parent_config`/`child_config` chain when it names one. Otherwise the root is built from
    /// the file's contents, not by SwiftLint's loader, and its file graph is empty.
    ///
    /// - `configPath` given: that file alone, like `swiftlint --config`. The caller should
    ///   not apply nested configs.
    /// - `configPath` nil: the workspace's own `.swiftlint.yml`, or SwiftLint's defaults
    ///   when there is none. Nested configs apply through `configuration(for:)`, after
    ///   ``checkNestedConfigs(for:root:fileGraph:)``. Call this with `URL.cwd` overridden to
    ///   `workspacePath`, which is where SwiftLint stops its nested-config search.
    static func root(
        configPath: URL?,
        workspacePath: URL
    ) throws -> (configuration: Configuration, fileGraph: Set<String>) {
        let file = configPath ?? workspacePath.appendingPathComponent(Configuration.defaultFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return (try Configuration(dict: [:], location: workspacePath), [])
        }

        let dict = try checkedDictionary(at: file)
        let configuration = try checkedConfiguration(dict, at: file)
        guard dict.referencesOtherConfigs else { return (configuration, []) }

        // Only SwiftLint's file loader follows parent/child references. Check the chain
        // first; if it still fails to load, fall back to the defaults with a printed warning,
        // as the CLI does for a config it discovers, rather than ending the app.
        let loaded = configPath ?? Configuration.defaultFileName.url()
        let rootPath = graphPath(of: loaded.filepath, relativeTo: URL.cwd.filepath)
        var fileGraph: Set<String> = [rootPath]
        try checkReferencedConfigs(of: dict, at: rootPath, fileGraph: &fileGraph)
        // Where SwiftLint can't build the chain (a cycle, say), it falls back with an empty
        // file graph, and its search stops at a config of the chain where the nested-config
        // check goes on: that check may then read more configs than SwiftLint loads, never fewer.
        return (
            Configuration(configurationFiles: configPath.map { [$0] } ?? [], useDefaultConfigOnFailure: true),
            fileGraph
        )
    }

    /// Checks the nested configs SwiftLint will load for `files`, retracing its search in
    /// `configuration(for:)` step by step. From each file's folder, spelled as SwiftLint's file
    /// walk spelled it, the search goes up one folder at a time:
    ///
    /// - It stops at `root`'s root directory, the workspace.
    /// - It passes over a `.swiftlint.yml` in `fileGraph`; `root(configPath:workspacePath:)`
    ///   has checked those.
    /// - It loads the first other `.swiftlint.yml` it meets, and stops.
    /// - Otherwise it goes on up to `/`.
    ///
    /// Since the folders are spelled as the walk spelled them, an `included` folder that is a
    /// link is searched through the link, not its target. In a workspace under `/private`, the
    /// walk can drop that prefix, so the search never meets the workspace and goes on above
    /// it. SwiftLint loads these configs in a way that ends the process on any error, so each
    /// one is checked first.
    ///
    /// `files` must be the ones the lint passes to `configuration(for:)`, and `root` and
    /// `fileGraph` must come from ``root(configPath:workspacePath:)``.
    static func checkNestedConfigs(
        for files: [SwiftLintFile],
        root: Configuration,
        fileGraph: Set<String>
    ) throws {
        // A folder searched once has had every config above it, up to where the search stops,
        // checked.
        var searched: Set<URL> = []
        for file in files {
            guard var directory = file.path?.deletingLastPathComponent() else { continue }
            while directory != root.rootDirectory, searched.insert(directory).inserted {
                let candidate = directory.appending(path: Configuration.defaultFileName, directoryHint: .notDirectory)
                if candidate.exists, !fileGraph.contains(candidate.filepath) {
                    _ = try checkedConfiguration(checkedDictionary(at: candidate), at: candidate)
                    break
                }
                guard directory.path != "/" else { break }
                directory = directory.deletingLastPathComponent()
            }
        }
    }

    /// Checks that `configuration` won't run custom rules: SwiftLint ends the process if it does.
    ///
    /// SwiftLint runs `custom_rules` without SourceKit when every custom rule it holds is set to
    /// `execution_mode: swiftsyntax`, yet still asks SourceKit for the file's syntax map to match
    /// them — and with SourceKit off, that request is a fatal error. Custom rules any one of which
    /// needs SourceKit are skipped, with a printed warning, so they are left to SwiftLint.
    static func checkCustomRules(of configuration: Configuration) throws {
        guard let customRules = configuration.rules.first(where: { type(of: $0).identifier == "custom_rules" }),
              !customRules.requiresSourceKit,
              holdsCustomRules(customRules) else {
            return
        }
        throw InProcessConfigurationError.customRulesNeedSourceKit
    }

    /// Whether the `custom_rules` rule holds any custom rule. With none it runs, and finds nothing;
    /// SwiftLint enables it in every configuration. Its type is internal to SwiftLint, so this reads
    /// its cache description: one entry per custom rule, after an optional default-mode line.
    private static func holdsCustomRules(_ rule: any Rule) -> Bool {
        guard let description = (rule as? any CacheDescriptionProvider)?.cacheDescription else { return true }
        return description.split(separator: "\n").contains { !$0.hasPrefix("default_execution_mode:") }
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
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
            dict = try parse(text)
        } catch {
            throw InProcessConfigurationError.unreadable(file: file, reason: String(describing: error))
        }
        // `${PWD}` would expand to the app's working directory, not the workspace's: setting it
        // for one lint would set it for the whole app, and every lint running at that moment.
        // A comment that mentions it is no matter: SwiftLint expands values, never comments.
        guard !namesWorkingDirectory(text) else {
            throw InProcessConfigurationError.usesWorkingDirectory(file: file)
        }
        if let pinned = dict["swiftlint_version"].map({ ($0 as? String) ?? String(describing: $0) }),
           pinned != Version.current.value {
            throw InProcessConfigurationError.versionMismatch(file: file, pinned: pinned)
        }
        return dict
    }

    /// Whether a key or value in `yaml`, rather than a comment, names `${PWD}`: once decoded,
    /// as `"\x24{PWD}"` is, and once the rest of the environment is expanded, as SwiftLint does.
    private static func namesWorkingDirectory(_ yaml: String) -> Bool {
        let marker = "\u{1}PWD\u{1}"
        let env = ProcessInfo.processInfo.environment.merging(["PWD": marker]) { $1 }
        guard let dict = try? parse(yaml, env: env) else { return true }
        func names(_ value: Any) -> Bool {
            switch value {
            case let string as String: string.contains(marker)
            case let array as [Any]: array.contains(where: names)
            case let dict as [String: Any]:
                dict.keys.contains { $0.contains(marker) } || dict.values.contains(where: names)
            default: false
            }
        }
        return names(dict)
    }

    private static func checkedConfiguration(_ dict: [String: Any], at file: URL) throws -> Configuration {
        do {
            return try Configuration(dict: dict, location: file.deletingLastPathComponent())
        } catch {
            throw InProcessConfigurationError.unreadable(file: file, reason: String(describing: error))
        }
    }

    /// Checks the local configs `dict` names under `parent_config`/`child_config`, and
    /// theirs in turn, adding each to `fileGraph`. `path` is where `dict` was read from, as
    /// SwiftLint's file graph spells it. Remote ones are left to SwiftLint.
    private static func checkReferencedConfigs(
        of dict: [String: Any],
        at path: String,
        fileGraph: inout Set<String>
    ) throws {
        for key in ["parent_config", "child_config"] {
            // SwiftLint's own test for a remote config; `http-base.yml` is a local file.
            guard let reference = dict[key] as? String,
                  !reference.hasPrefix("http://"), !reference.hasPrefix("https://") else { continue }
            // The folder as SwiftLint's `Vertex.rootDirectory` takes it.
            // swiftlint:disable:next legacy_objc_type
            let folder = (path as NSString).deletingLastPathComponent
            let referencedPath = graphPath(of: reference, relativeTo: folder)
            guard fileGraph.insert(referencedPath).inserted,
                  FileManager.default.fileExists(atPath: referencedPath) else { continue }
            let referenced = URL(fileURLWithPath: referencedPath)
            let referencedDict = try checkedDictionary(at: referenced)
            _ = try checkedConfiguration(referencedDict, at: referenced)
            try checkReferencedConfigs(of: referencedDict, at: referencedPath, fileGraph: &fileGraph)
        }
    }

    /// `reference` as SwiftLint's file graph spells a config it names from `folder`
    /// (`Configuration.FileGraph.Vertex`), which is how its nested-config search compares them.
    private static func graphPath(of reference: String, relativeTo folder: String) -> String {
        reference.url(relativeTo: folder.url(directoryHint: .isDirectory), directoryHint: .notDirectory).filepath
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
