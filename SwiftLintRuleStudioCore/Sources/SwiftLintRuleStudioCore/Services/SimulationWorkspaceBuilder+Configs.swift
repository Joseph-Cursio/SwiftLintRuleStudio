//
//  SimulationWorkspaceBuilder+Configs.swift
//  SwiftLintRuleStudio
//
//  Reading the configs a mirror holds, ready to be written with a rule enabled.
//

import Foundation
import Yams

extension SimulationWorkspaceBuilder {
    /// A mirror's configs, read, and the custom rules they define.
    struct LoadedConfigs {
        let entries: [SimulationWorkspace.ConfigEntry]
        let customRuleIds: Set<String>
    }

    /// Loads the root and every nested `.swiftlint.yml`, paired with its path in the
    /// mirror — including configs reached through a symlinked folder, which SwiftLint
    /// applies there. Guarantees a root config exists (seeded from
    /// `baseConfigPath`/`workspace.configPath`, or empty) so the enabled rule always has
    /// somewhere to live.
    ///
    /// A config with nothing in it, or only comments, is mirrored empty: SwiftLint finds it and
    /// looks no further up, so leaving it out would hand its folder a config further up. A root
    /// config SwiftLint can't read it replaces with its defaults, and so does the mirror; any
    /// other it stops on, so the simulation stops too (``MirrorUnsupportedSetupError``).
    func loadConfigs(
        of plan: WorkspaceMirrorPlan,
        for workspace: Workspace,
        baseConfigPath: URL?
    ) throws -> LoadedConfigs {
        var entries: [SimulationWorkspace.ConfigEntry] = []
        var customRuleIds: Set<String> = []
        var haveRoot = false
        let rootPrefix = plan.lintRoot + "/"

        for file in plan.configs {
            // Relative to the lint root; a config beside it, outside the workspace, climbs out.
            let relative = file.path.hasPrefix(rootPrefix)
                ? String(file.path.dropFirst(rootPrefix.count))
                : WorkspaceMirrorPlan.relative(from: plan.lintRoot, to: file.path)
            let isRoot = relative == ConfigTreeDiscovery.configFileName
            // The seed below stands in for an unreadable root config.
            guard var config = try Self.read(file, isRoot: isRoot) else { continue }
            Self.prepare(&config, readFrom: file.source)
            customRuleIds.formUnion(RawConfigKeys.read(file.source)?.customRuleIds ?? [])
            if isRoot {
                haveRoot = true
            }
            let isRootConfiguration = isRoot || plan.referencedConfigPaths.contains(file.path)
            entries.append(.init(
                relativePath: relative,
                original: config,
                isRootConfiguration: isRootConfiguration,
                baseline: Self.baseline(of: config)
            ))
        }

        if !haveRoot {
            var seed = seedRootConfig(baseConfigPath: baseConfigPath, workspace: workspace)
            if let source = rootConfigFile(for: workspace, baseConfigPath: baseConfigPath) {
                Self.prepare(&seed, readFrom: source)
                customRuleIds.formUnion(RawConfigKeys.read(source)?.customRuleIds ?? [])
            }
            entries.insert(
                .init(
                    relativePath: ConfigTreeDiscovery.configFileName,
                    original: seed,
                    isRootConfiguration: true,
                    baseline: Self.baseline(of: seed)
                ),
                at: 0
            )
        }

        return LoadedConfigs(entries: entries, customRuleIds: customRuleIds)
    }

    /// The config `file` holds; empty for one with nothing in it, nil for a root config SwiftLint
    /// can't read. Any other it can't read SwiftLint stops on, and so does the simulation.
    private static func read(
        _ file: WorkspaceMirrorPlan.File,
        isRoot: Bool
    ) throws -> YAMLConfigurationEngine.YAMLConfig? {
        do {
            return try YAMLConfigurationEngine.loadConfig(at: file.source)
        } catch {
            if isRoot { return nil }
            guard RawConfigKeys.hasContent(file.source) else { return YAMLConfigurationEngine.YAMLConfig() }
            throw MirrorUnsupportedSetupError(
                reason: "SwiftLint can't read the configuration at \(file.source.path) "
                    + "(\(error.localizedDescription)), and stops on it."
            )
        }
    }

    /// Readies a config read from `source` for the mirror:
    /// - puts back `excluded: Pods` and `included: Sources` — SwiftLint's single-string form —
    ///   which the engine reads as nothing and would write back as nothing (until it reads them);
    /// - drops `write_baseline`, which would have a simulation overwrite the user's baseline
    ///   when the path is absolute, and write one nobody reads when it isn't;
    /// - points `baseline` at the user's file, by its absolute path — SwiftLint only reads it —
    ///   until each rule's write puts a copy of it in the mirror (see ``MirrorBaseline``).
    static func prepare(_ config: inout YAMLConfigurationEngine.YAMLConfig, readFrom source: URL) {
        if let raw = RawConfigKeys.read(source) {
            if config.excluded == nil, !raw.excluded.isEmpty { config.excluded = raw.excluded }
            if config.included == nil, !raw.included.isEmpty { config.included = raw.included }
        }
        config.passthroughNodes["write_baseline"] = nil
        config.keyOrder.removeAll { $0 == "write_baseline" }
        if let baseline = config.passthroughNodes["baseline"]?.string, !baseline.hasPrefix("/") {
            // SwiftLint reads it relative to the config's own folder.
            let original = source.deletingLastPathComponent().appendingPathComponent(baseline).standardizedFileURL
            config.passthroughNodes["baseline"] = Node(original.path)
        }
    }

    /// The file a prepared config's `baseline` names.
    private static func baseline(of config: YAMLConfigurationEngine.YAMLConfig) -> URL? {
        config.passthroughNodes["baseline"]?.string.map { URL(fileURLWithPath: $0) }
    }

    private func seedRootConfig(
        baseConfigPath: URL?,
        workspace: Workspace
    ) -> YAMLConfigurationEngine.YAMLConfig {
        if let base = baseConfigPath ?? workspace.configPath,
           fileManager.fileExists(atPath: base.path) {
            if let config = try? YAMLConfigurationEngine.loadConfig(at: base) {
                return config
            }
        }
        return YAMLConfigurationEngine.YAMLConfig()
    }
}
