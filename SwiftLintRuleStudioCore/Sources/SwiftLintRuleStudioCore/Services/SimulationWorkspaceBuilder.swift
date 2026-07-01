//
//  SimulationWorkspaceBuilder.swift
//  SwiftLintRuleStudio
//
//  Builds a throwaway "shadow" copy of a workspace so a rule's impact can be
//  measured without ever touching the user's real files.
//

import Foundation

/// A non-destructive mirror of a workspace. Hand ``root`` to
/// `SwiftLintCLIProtocol.executeLintCommand(configPath:workspacePath:)` as the
/// workspace path (with `configPath: nil`) so SwiftLint lints the mirror in its
/// normal nested-config-aware mode.
final class SimulationWorkspace {

    struct ConfigEntry {
        let relativePath: String
        let original: YAMLConfigurationEngine.YAMLConfig
    }

    /// Root of the shadow tree.
    let root: URL

    private let configs: [ConfigEntry]
    private let fileManager: FileManager

    init(root: URL, configs: [ConfigEntry], fileManager: FileManager) {
        self.root = root
        self.configs = configs
        self.fileManager = fileManager
    }

    /// Rewrites every mirrored `.swiftlint.yml` so `ruleId` is enabled — in the
    /// root *and* every nested config. Each call starts fresh from the cached
    /// originals, so simulating rule B never leaves rule A enabled from a prior
    /// call (important for batch audits that reuse one workspace).
    func applyRule(
        _ ruleId: String,
        isOptIn: Bool,
        isAnalyzer: Bool,
        parameterOverrides: [String: AnyCodable]?
    ) throws {
        for entry in configs {
            var config = entry.original
            ConfigRuleEnabler.enableRule(
                ruleId,
                in: &config,
                isOptIn: isOptIn,
                isAnalyzer: isAnalyzer,
                parameterOverrides: parameterOverrides
            )
            let destination = root.appendingPathComponent(entry.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let engine = YAMLConfigurationEngine(configPath: destination)
            engine.updateConfig(config)
            try engine.save(config: config, createBackup: false)
        }
    }

    /// Removes the shadow tree. Safe to call more than once.
    func cleanup() {
        try? fileManager.removeItem(at: root)
    }
}

/// The YAML mutation that turns a rule on: sets it enabled, routes it into
/// `opt_in_rules` / `analyzer_rules` as required, adds it to `only_rules` when a
/// whitelist is present, and removes it from `disabled_rules`. Preserves the
/// config's `included:`/`excluded:` exactly as written — in the mirror those
/// relative paths resolve correctly, so no absolutizing is needed.
enum ConfigRuleEnabler {

    static func enableRule(
        _ ruleId: String,
        in config: inout YAMLConfigurationEngine.YAMLConfig,
        isOptIn: Bool,
        isAnalyzer: Bool,
        parameterOverrides: [String: AnyCodable]? = nil
    ) {
        var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: true)
        ruleConfig.enabled = true
        if let overrides = parameterOverrides, !overrides.isEmpty {
            var merged = ruleConfig.parameters ?? [:]
            for (key, value) in overrides {
                merged[key] = value
            }
            ruleConfig.parameters = merged
        }
        config.rules[ruleId] = ruleConfig

        if isAnalyzer {
            appendUnique(ruleId, to: &config.analyzerRules)
        } else if isOptIn {
            appendUnique(ruleId, to: &config.optInRules)
        }

        if config.onlyRules != nil {
            appendUnique(ruleId, to: &config.onlyRules)
        }

        if var disabledRules = config.disabledRules {
            disabledRules.removeAll { $0 == ruleId }
            config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
        }
    }

    private static func appendUnique(_ ruleId: String, to list: inout [String]?) {
        var current = list ?? []
        if !current.contains(ruleId) {
            current.append(ruleId)
            list = current
        }
    }
}

/// Builds a ``SimulationWorkspace`` — a non-destructive mirror of a real
/// workspace used to measure a rule's impact.
///
/// Why a mirror instead of a single temp config: SwiftLint discovers its
/// configuration from the working directory and merges *nested* `.swiftlint.yml`
/// files from the linted paths. Passing `--config` would disable that nested
/// resolution, and writing a lone temp config outside the workspace is simply
/// ignored (SwiftLint finds the workspace's own config from `cwd` instead). To
/// enable a rule everywhere while still honoring nested excludes/relaxations, the
/// modified configs must live at their real relative locations on disk — but we
/// must not mutate the user's tree. So we mirror the workspace: `.swift` sources
/// are hardlinked (copied only on a cross-volume fallback) and every
/// `.swiftlint.yml` is reproduced with the target rule enabled. SwiftLint then
/// lints the mirror in its normal (`.effective`) mode.
struct SimulationWorkspaceBuilder {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Mirrors `workspace` into a fresh temp directory and returns a
    /// ``SimulationWorkspace`` ready for ``SimulationWorkspace/applyRule(_:isOptIn:isAnalyzer:parameterOverrides:)``.
    ///
    /// - Parameter baseConfigPath: A config to seed the root from when the
    ///   workspace has no root `.swiftlint.yml` of its own. Nested configs are
    ///   always discovered from the workspace tree regardless.
    func makeWorkspace(for workspace: Workspace, baseConfigPath: URL?) throws -> SimulationWorkspace {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        try mirrorSwiftFiles(from: workspace.path, into: root)
        let configs = loadConfigs(for: workspace, baseConfigPath: baseConfigPath)
        return SimulationWorkspace(root: root, configs: configs, fileManager: fileManager)
    }

    // MARK: - Mirroring

    /// Hardlinks every `.swift` file under `source` into `destinationRoot` at the
    /// same relative path, skipping the canonical build/dependency directories.
    /// Sources are read-only during a lint, so sharing inodes is safe; a link
    /// failure (e.g. `EXDEV` across volumes) falls back to a copy.
    private func mirrorSwiftFiles(from source: URL, into destinationRoot: URL) throws {
        let excludedDirectories = Set(DefaultExclusions.directories)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

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

            guard url.pathExtension == "swift" else { continue }

            let relative = Self.relativePath(of: url, underRoot: source)
            let destination = destinationRoot.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try fileManager.linkItem(at: url, to: destination)
            } catch {
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: url, to: destination)
            }
        }
    }

    // MARK: - Configs

    /// Loads the root and every nested `.swiftlint.yml`, paired with its path
    /// relative to the workspace root. Guarantees a root config exists (seeded
    /// from `baseConfigPath`/`workspace.configPath`, or empty) so the enabled rule
    /// always has somewhere to live.
    private func loadConfigs(
        for workspace: Workspace,
        baseConfigPath: URL?
    ) -> [SimulationWorkspace.ConfigEntry] {
        var entries: [SimulationWorkspace.ConfigEntry] = []
        var haveRoot = false

        for url in ConfigTreeDiscovery.configFileURLs(in: workspace.path) {
            let engine = YAMLConfigurationEngine(configPath: url)
            // Tolerate an empty or malformed `.swiftlint.yml`: skipping it lets the
            // mirror inherit the parent config for that subtree — which is exactly
            // what an empty nested config means to SwiftLint — rather than aborting
            // the whole simulation.
            guard (try? engine.load()) != nil else { continue }
            let relative = Self.relativePath(of: url, underRoot: workspace.path)
            if relative == ConfigTreeDiscovery.configFileName {
                haveRoot = true
            }
            entries.append(.init(relativePath: relative, original: engine.getConfig()))
        }

        if !haveRoot {
            let seed = seedRootConfig(baseConfigPath: baseConfigPath, workspace: workspace)
            entries.insert(
                .init(relativePath: ConfigTreeDiscovery.configFileName, original: seed),
                at: 0
            )
        }

        return entries
    }

    private func seedRootConfig(
        baseConfigPath: URL?,
        workspace: Workspace
    ) -> YAMLConfigurationEngine.YAMLConfig {
        if let base = baseConfigPath ?? workspace.configPath,
           fileManager.fileExists(atPath: base.path) {
            let engine = YAMLConfigurationEngine(configPath: base)
            if (try? engine.load()) != nil {
                return engine.getConfig()
            }
        }
        return YAMLConfigurationEngine.YAMLConfig()
    }

    // MARK: - Helpers

    /// Path of `url` relative to `root`, computed by path-component prefix so it
    /// is stable regardless of `/var` vs `/private/var` symlink spelling (both
    /// URLs are derived from the same root, so their normalized components share a
    /// prefix). Falls back to the last component if `url` is not under `root`.
    static func relativePath(of url: URL, underRoot root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
