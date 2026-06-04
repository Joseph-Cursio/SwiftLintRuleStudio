//
//  ConfigTreeDiscovery.swift
//  SwiftLintRuleStudio
//
//  Walks a workspace for every `.swiftlint.yml`, parses each, and links them
//  into a ``ConfigTree`` by directory nesting. This is the data layer behind the
//  Config Tree view and the per-folder resolved-config inspector.
//  See docs/nested-config-visibility.md.
//

import Foundation

/// Discovers the nested `.swiftlint.yml` configuration tree for a workspace.
public struct ConfigTreeDiscovery {
    /// The canonical SwiftLint configuration file name. SwiftLint always looks
    /// for this exact name when resolving nested configs.
    nonisolated public static let configFileName = ".swiftlint.yml"

    /// Creates a discovery service.
    nonisolated public init() {}

    // MARK: - File discovery

    /// Finds every `.swiftlint.yml` under `workspaceRoot`, skipping build,
    /// dependency, and metadata directories (``DefaultExclusions/directories``).
    ///
    /// `.swiftlint.yml` is a hidden file, so the enumerator cannot skip hidden
    /// files; instead excluded directories are pruned by name as they are met.
    /// Returns the configs sorted by path so the root sorts first.
    public static func configFileURLs(in workspaceRoot: URL) -> [URL] {
        let fileManager = FileManager.default
        let excludedDirectories = Set(DefaultExclusions.directories)

        guard let enumerator = fileManager.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) ?? false

            if isDirectory {
                if excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if url.lastPathComponent == configFileName {
                results.append(url)
            }
        }

        return results.sorted { $0.path < $1.path }
    }

    // MARK: - Tree discovery

    /// Discovers and parses the full config tree for `workspaceRoot`.
    ///
    /// Each `.swiftlint.yml` is parsed with ``YAMLConfigurationEngine``; a config
    /// that fails to parse is still included as a node, with its
    /// ``DiscoveredConfig/parseError`` set so the UI can surface it rather than
    /// silently dropping it.
    public func discover(in workspaceRoot: URL) -> ConfigTree {
        let rootComponents = workspaceRoot.standardizedFileURL.pathComponents
        let urls = Self.configFileURLs(in: workspaceRoot)

        let pendings = urls.map { url in
            Self.parse(url: url, rootComponents: rootComponents)
        }

        let configs = pendings.map { pending -> DiscoveredConfig in
            let summary: ConfigSummary
            if let parsed = pending.config {
                summary = Self.summarize(parsed)
            } else {
                summary = .empty
            }
            return DiscoveredConfig(
                id: pending.id,
                configPath: pending.configPath,
                directoryPath: pending.directoryPath,
                relativePath: pending.relativePath,
                depth: pending.depth,
                isRoot: pending.isRoot,
                parentID: Self.parentID(for: pending, among: pendings),
                config: pending.config,
                parseError: pending.parseError,
                summary: summary
            )
        }

        return ConfigTree(workspaceRoot: workspaceRoot, configs: configs)
    }

    // MARK: - Internals

    /// A config's path/parse information before parent links are resolved.
    private struct PendingConfig {
        let id = UUID()
        let configPath: URL
        let directoryPath: URL
        /// Path components of the governed directory (used for ancestor lookup).
        let directoryComponents: [String]
        let relativePath: String
        let depth: Int
        let isRoot: Bool
        let config: YAMLConfig?
        let parseError: String?
    }

    private static func parse(url: URL, rootComponents: [String]) -> PendingConfig {
        let components = url.standardizedFileURL.pathComponents
        let directoryComponents = Array(components.dropLast())
        // Components below the workspace root, e.g. ["Tests", ".swiftlint.yml"].
        let relativeComponents = Array(components.suffix(
            from: min(rootComponents.count, components.count)
        ))
        let relativePath = relativeComponents.isEmpty
            ? configFileName
            : relativeComponents.joined(separator: "/")
        let depth = max(0, directoryComponents.count - rootComponents.count)

        var parsedConfig: YAMLConfig?
        var parseError: String?
        do {
            let engine = YAMLConfigurationEngine(configPath: url)
            try engine.load()
            parsedConfig = engine.getConfig()
        } catch {
            parseError = error.localizedDescription
        }

        return PendingConfig(
            configPath: url,
            directoryPath: url.deletingLastPathComponent(),
            directoryComponents: directoryComponents,
            relativePath: relativePath,
            depth: depth,
            isRoot: depth == 0,
            config: parsedConfig,
            parseError: parseError
        )
    }

    /// Resolves a config's parent: the discovered config in the *nearest*
    /// ancestor directory.
    private static func parentID(
        for pending: PendingConfig,
        among all: [PendingConfig]
    ) -> UUID? {
        var nearest: PendingConfig?
        let nodeComponents = pending.directoryComponents

        for candidate in all where candidate.id != pending.id {
            let ancestorComponents = candidate.directoryComponents
            guard ancestorComponents.count < nodeComponents.count else { continue }
            guard Array(nodeComponents.prefix(ancestorComponents.count)) == ancestorComponents else {
                continue
            }
            if let current = nearest {
                if ancestorComponents.count > current.directoryComponents.count {
                    nearest = candidate
                }
            } else {
                nearest = candidate
            }
        }

        return nearest?.id
    }

    private static func summarize(_ config: YAMLConfig) -> ConfigSummary {
        ConfigSummary(
            disabledRuleCount: config.disabledRules?.count ?? 0,
            optInRuleCount: config.optInRules?.count ?? 0,
            analyzerRuleCount: config.analyzerRules?.count ?? 0,
            configuredRuleCount: config.rules.count,
            onlyRules: config.onlyRules,
            setsExcluded: !(config.excluded?.isEmpty ?? true),
            setsIncluded: !(config.included?.isEmpty ?? true),
            setsReporter: config.reporter != nil
        )
    }
}
