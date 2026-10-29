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
import Yams

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
        let rootGraph = Self.rootGraph(among: pendings, workspaceRoot: workspaceRoot)

        let configs = pendings.map { pending -> DiscoveredConfig in
            DiscoveredConfig(
                configPath: pending.configPath,
                directoryPath: pending.directoryPath,
                relativePath: pending.relativePath,
                depth: pending.depth,
                isRoot: pending.isRoot,
                parentID: Self.parentID(for: pending, among: pendings),
                config: pending.config,
                parseError: pending.parseError,
                summary: pending.config.map(Self.summarize) ?? .empty,
                rootGraphPosition: rootGraph.positions[pending.configPath.standardizedFileURL.path]
            )
        }

        return ConfigTree(workspaceRoot: workspaceRoot, configs: configs, referencedConfigs: rootGraph.referenced)
    }

    /// Where SwiftLint keeps its copy of the remote config at `reference`, which it
    /// fetches whenever it lints in `workspaceRoot` and falls back to when it can't
    /// (`Configuration.FileGraph.FilePath`'s remote config cache).
    public static func remoteConfigCacheURL(for reference: String, in workspaceRoot: URL) -> URL {
        var name = reference
        for character in [":", "<", ">", "\"", "/", "\\", "|", "?", "*"] {
            name = name.replacingOccurrences(of: character, with: "_")
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return workspaceRoot
            .appendingPathComponent(".swiftlint/RemoteConfigCache/v1", isDirectory: true)
            .appendingPathComponent(name + ".yml")
    }

    // MARK: - Internals

    /// A config's path/parse information before parent links are resolved.
    private struct PendingConfig {
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
        let loaded = load(url)

        return PendingConfig(
            configPath: url,
            directoryPath: url.deletingLastPathComponent(),
            directoryComponents: directoryComponents,
            relativePath: relativePath,
            depth: depth,
            isRoot: depth == 0,
            config: loaded.config,
            parseError: loaded.parseError
        )
    }

    /// Resolves a config's parent: the discovered config in the *nearest*
    /// ancestor directory.
    ///
    /// Self-exclusion compares paths, which is what it always meant. It used to compare a minted
    /// `UUID` that existed for no other purpose — two configs are the same config when they are the
    /// same file.
    private static func parentID(
        for pending: PendingConfig,
        among all: [PendingConfig]
    ) -> URL? {
        var nearest: PendingConfig?
        let nodeComponents = pending.directoryComponents

        for candidate in all where candidate.configPath != pending.configPath {
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

        return nearest?.configPath
    }

    /// The configs the root config pulls in: each discovered one's place in the
    /// chain counted from the root, by path (see ``DiscoveredConfig/rootGraphPosition``),
    /// and the others, read here.
    private struct RootGraph {
        var positions: [String: Int] = [:]
        /// See ``ConfigTree/referencedConfigs``.
        var referenced: [DiscoveredConfig] = []
    }

    /// A config on the walk of the root's chain, as the walk needs it.
    private struct GraphNode {
        let config: YAMLConfig?
        /// The folder SwiftLint reads the config's references from.
        let folder: URL
        let isRemote: Bool
    }

    /// Follows the root config's `parent_config` and `child_config` references.
    ///
    /// SwiftLint follows `parent_config` up from the root and `child_config` down
    /// from it, each reference read relative to the folder of the config that
    /// writes it; a remote config's, relative to the folder of the config that
    /// pulled it in. The chain must be linear — SwiftLint refuses a config with two
    /// parents or two children — so following one key each way finds all of it.
    ///
    /// A reference to one of the workspace's `.swiftlint.yml` files places it in
    /// the chain. Any other file — outside the workspace, or under another name —
    /// is read as a referenced config, and so is a remote one, from the copy
    /// SwiftLint keeps in the workspace. The walk stops at a file that doesn't
    /// exist, which SwiftLint ignores; at a remote config it hasn't fetched yet,
    /// whose references can't be read; at a local reference in a remote config,
    /// which SwiftLint refuses; and where the chain comes back on itself. A nested
    /// config's own references are not followed: SwiftLint ignores them.
    private static func rootGraph(among pendings: [PendingConfig], workspaceRoot: URL) -> RootGraph {
        guard let root = pendings.first(where: \.isRoot) else { return RootGraph() }
        let byPath = Dictionary(pendings.map { ($0.configPath.standardizedFileURL.path, $0) }) { first, _ in first }

        var graph = RootGraph()
        var visited: Set<String> = [root.configPath.standardizedFileURL.path]
        for (key, step) in [("parent_config", -1), ("child_config", 1)] {
            var current = GraphNode(config: root.config, folder: root.directoryPath, isRemote: false)
            var position = 0
            while let written = current.config?.passthroughNodes[key]?.string {
                position += step
                if written.hasPrefix("http://") || written.hasPrefix("https://") {
                    guard let url = URL(string: written), visited.insert(written).inserted else { break }
                    let remote = remoteConfig(
                        at: url,
                        written: written,
                        pulledInFrom: current.folder,
                        position: position,
                        workspaceRoot: workspaceRoot
                    )
                    graph.referenced.append(remote)
                    current = GraphNode(config: remote.config, folder: current.folder, isRemote: true)
                    continue
                }
                let file = (written.hasPrefix("/")
                    ? URL(fileURLWithPath: written)
                    : current.folder.appendingPathComponent(written)).standardizedFileURL
                guard !current.isRemote, visited.insert(file.path).inserted else { break }
                if let discovered = byPath[file.path] {
                    graph.positions[file.path] = position
                    current = GraphNode(config: discovered.config, folder: discovered.directoryPath, isRemote: false)
                } else {
                    guard FileManager.default.fileExists(atPath: file.path) else { break }
                    let referenced = referencedFile(at: file, position: position, workspaceRoot: workspaceRoot)
                    graph.referenced.append(referenced)
                    current = GraphNode(config: referenced.config, folder: referenced.directoryPath, isRemote: false)
                }
            }
        }
        graph.referenced.sort { ($0.rootGraphPosition ?? 0) < ($1.rootGraphPosition ?? 0) }
        return graph
    }

    /// A file the root config pulls in that isn't one of the workspace's own
    /// `.swiftlint.yml` files.
    private static func referencedFile(at file: URL, position: Int, workspaceRoot: URL) -> DiscoveredConfig {
        let loaded = load(file)
        return DiscoveredConfig(
            configPath: file,
            directoryPath: file.deletingLastPathComponent(),
            relativePath: path(of: file, from: workspaceRoot),
            depth: 0,
            isRoot: false,
            parentID: nil,
            config: loaded.config,
            parseError: loaded.parseError,
            summary: loaded.config.map(summarize) ?? .empty,
            rootGraphPosition: position,
            origin: .referencedFile
        )
    }

    /// A remote config the root config pulls in, as SwiftLint last fetched it into
    /// the workspace; with no config when it hasn't yet.
    private static func remoteConfig(
        at url: URL,
        written: String,
        pulledInFrom folder: URL,
        position: Int,
        workspaceRoot: URL
    ) -> DiscoveredConfig {
        let cached = remoteConfigCacheURL(for: written, in: workspaceRoot)
        let loaded = FileManager.default.fileExists(atPath: cached.path)
            ? load(cached)
            : (config: nil, parseError: nil)
        return DiscoveredConfig(
            configPath: url,
            directoryPath: folder,
            relativePath: written,
            depth: 0,
            isRoot: false,
            parentID: nil,
            config: loaded.config,
            parseError: loaded.parseError,
            summary: loaded.config.map(summarize) ?? .empty,
            rootGraphPosition: position,
            origin: .remote
        )
    }

    /// `url`'s path from the folder `base`, climbing out of it with `..` where it
    /// lies outside, as a config in `base` would name it: `../../.swiftlint.yml`.
    /// `.` for `base` itself.
    nonisolated static func path(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        let common = zip(baseComponents, components).prefix { $0 == $1 }.count
        let path = Array(repeating: "..", count: baseComponents.count - common) + components.dropFirst(common)
        return path.isEmpty ? "." : path.joined(separator: "/")
    }

    private static func load(_ file: URL) -> (config: YAMLConfig?, parseError: String?) {
        do {
            return (try YAMLConfigurationEngine.loadConfig(at: file), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private static func summarize(_ config: YAMLConfig) -> ConfigSummary {
        ConfigSummary(
            disabledRuleCount: config.disabledRules?.count ?? 0,
            optInRuleCount: config.optInRules?.count ?? 0,
            analyzerRuleCount: config.analyzerRules?.count ?? 0,
            configuredRuleCount: config.rules.count,
            onlyRules: config.usesOnlyRules ? config.onlyRules : nil,
            setsExcluded: !(config.excluded?.isEmpty ?? true),
            setsIncluded: !(config.included?.isEmpty ?? true),
            setsReporter: config.reporter != nil
        )
    }
}
