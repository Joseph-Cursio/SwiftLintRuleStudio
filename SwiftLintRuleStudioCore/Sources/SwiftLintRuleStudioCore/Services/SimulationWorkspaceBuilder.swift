//
//  SimulationWorkspaceBuilder.swift
//  SwiftLintRuleStudio
//
//  Builds a throwaway "shadow" copy of a workspace so a rule's impact can be
//  measured without ever touching the user's real files.
//

import Foundation
import SwiftLintCLISeam
import Yams

/// A non-destructive mirror of a workspace. Hand ``root`` to
/// `SwiftLintCLIProtocol.executeLintCommand(configPath:workspacePath:)` as the
/// workspace path (with `configPath: nil`) so SwiftLint lints the mirror in its
/// normal nested-config-aware mode.
final class SimulationWorkspace {

    struct ConfigEntry {
        let relativePath: String
        let original: YAMLConfigurationEngine.YAMLConfig
        /// The root config, or one it pulls in: the configuration Enable changes. A nested
        /// config Enable leaves alone, and so does the simulation — its `disabled_rules` still
        /// turn the rule off beneath it once it is enabled.
        var isRootConfiguration = false
        /// The user's file its `baseline` names, which the mirror gets a copy of.
        var baseline: URL?
    }

    /// Root of the shadow tree. It moves on every ``applyRule(_:isOptIn:isAnalyzer:parameterOverrides:)``,
    /// so read it after applying a rule.
    private(set) var root: URL

    /// The folder that moves on every rule: the root's container when it has one, which also
    /// holds the mirrors of folders outside the workspace that links point into, or the root.
    private var movingFolder: URL
    private let rootInMovingFolder: String?
    private let externalFolders: [WorkspaceMirrorPlan.ExternalFolder]
    /// The workspace's real path, whose copy is the root.
    private let workspaceRoot: String?
    let configs: [ConfigEntry]
    /// The names the configs' `custom_rules` define, which SwiftLint reports their violations under.
    let customRuleIds: Set<String>
    private let fileManager: FileManager
    private let lock: MirrorLock?
    private var isRemoved = false

    /// - Parameters:
    ///   - container: The folder holding `root` and `externalFolders`, moved as one so the
    ///     links between them keep resolving; nil when `root` stands alone.
    ///   - configs: Each config's path is relative to `root`, and may climb out of it into
    ///     `container`.
    ///   - lock: The lock the mirror holds until it is removed, so no sweep removes it first.
    ///   - rootInContainer: `root`'s path in `container`; its last component when nil.
    init(
        root: URL,
        configs: [ConfigEntry],
        fileManager: FileManager,
        container: URL? = nil,
        externalFolders: [WorkspaceMirrorPlan.ExternalFolder] = [],
        lock: MirrorLock? = nil,
        rootInContainer: String? = nil,
        customRuleIds: Set<String> = [],
        workspaceRoot: String? = nil
    ) {
        self.root = root
        self.movingFolder = container ?? root
        self.rootInMovingFolder = container == nil ? nil : rootInContainer ?? root.lastPathComponent
        self.externalFolders = externalFolders
        self.configs = configs
        self.customRuleIds = customRuleIds
        self.workspaceRoot = workspaceRoot
        self.fileManager = fileManager
        self.lock = lock
    }

    /// The rule ids whose violations count for `ruleId`: its own, or for `custom_rules` the
    /// name of every custom rule — SwiftLint reports each under its own name.
    func reportedRuleIds(for ruleId: String) -> Set<String> {
        ruleId == "custom_rules" ? customRuleIds.union([ruleId]) : [ruleId]
    }

    /// Puts a path SwiftLint reports in a mirrored outside folder back at the real one —
    /// where the mirror is now, so read it after applying a rule.
    var pathMapping: MirrorPathMapping {
        MirrorPathMapping(container: movingFolder, folders: externalFolders)
    }

    /// The real path of a file SwiftLint linted at `path` in a mirrored folder outside the
    /// workspace, or nil when `path` isn't in one. SwiftLint reports such a file at its real
    /// path, and in the mirror that is the mirror's copy.
    func originalPath(ofLinted path: String) -> String? {
        pathMapping.originalPath(of: path)
    }

    /// Rewrites the mirror's root config, and the configs it pulls in, so `ruleId` is enabled,
    /// as Enable will enable it; nested configs are written as they are, so one that disables
    /// the rule still disables it beneath it, as it will after Enable. Each call starts fresh
    /// from the cached originals, so simulating rule B never leaves rule A enabled from a prior
    /// call (important for batch audits that reuse one workspace).
    ///
    /// When the rule will be linted alone (``onlyRule(for:)``), a nested `only_rules` that leaves
    /// it out is written as the `disabled_rules` it then amounts to; see ``keepsOff(_:_:)``.
    ///
    /// Each config written is read back as SwiftLint will read it. One it can't read, SwiftLint
    /// would replace with its defaults — every rule measuring as if nothing were configured — so
    /// that throws ``MirrorConfigWriteError`` instead of linting.
    ///
    /// Each call also moves the mirror to a new path. The sandboxed edition runs
    /// SwiftLint in-process, where SwiftLint caches every config it loads from a file
    /// by path, not contents. Its lint clears those caches when it starts and ends, so
    /// this is a second line of defence: should two lints of the mirror ever overlap,
    /// rule B's still couldn't read the configs rule A's left there. A rename is cheap
    /// and keeps the hardlinks.
    func applyRule(
        _ ruleId: String,
        isOptIn: Bool,
        isAnalyzer: Bool,
        parameterOverrides: [String: AnyCodable]?
    ) throws {
        let freshFolder = movingFolder.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: movingFolder, to: freshFolder)
        movingFolder = freshFolder
        root = rootInMovingFolder.map { freshFolder.appendingPathComponent($0, isDirectory: true) } ?? freshFolder
        let isLintedAlone = onlyRule(for: ruleId) != nil

        for (index, entry) in configs.enumerated() {
            // A rejected root configuration is measured as the app will repair it, which is also
            // how `RuleEnablementResolver` shows it; as written it couldn't be saved. A nested
            // config Enable doesn't touch is mirrored as it is.
            var config = entry.isRootConfiguration ? entry.original.normalizedRuleLists() : entry.original
            let destination = root.appendingPathComponent(entry.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let baseline = entry.baseline, let copy = try MirrorBaseline.write(
                baseline,
                besideConfigAt: destination,
                index: index,
                places: baselinePlaces
            ) {
                config.passthroughNodes["baseline"] = Node(copy)
            }
            if entry.isRootConfiguration {
                ConfigRuleEnabler.enableRule(
                    ruleId,
                    in: &config,
                    isOptIn: isOptIn,
                    isAnalyzer: isAnalyzer,
                    parameterOverrides: parameterOverrides
                )
            } else if isLintedAlone, keepsOff(ruleId, entry) {
                config.onlyRules = nil
                config.disabledRules = [ruleId]
            }
            try YAMLConfigurationEngine.save(config, to: destination, createBackup: false)
            try MirrorConfigWriteError.checkReadable(destination, writtenFor: entry.relativePath)
        }
    }

    /// Where the real folders a baseline may name by their whole path are in the mirror now.
    private var baselinePlaces: [MirrorBaseline.Place] {
        let folders = externalFolders.map {
            MirrorBaseline.Place(real: $0.original.path, mirror: movingFolder.appendingPathComponent($0.path).path)
        }
        guard let workspaceRoot else { return folders }
        return [MirrorBaseline.Place(real: workspaceRoot, mirror: nil)] + folders
    }

    /// Removes the shadow tree, then lets go of its lock. Safe to call more than once.
    func cleanup() {
        guard !isRemoved else { return }
        isRemoved = true
        try? fileManager.removeItem(at: movingFolder)
        lock?.release()
    }

    /// ``cleanup()`` off the main actor: removing a mirror of tens of thousands of files takes
    /// seconds, which would freeze the app at the end of every simulation.
    func cleanupInBackground() {
        guard !isRemoved else { return }
        isRemoved = true
        let folder = movingFolder
        let lock = lock
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folder)
            lock?.release()
        }
    }
}

/// The YAML mutation that turns a rule on: sets it enabled, applies any parameter
/// overrides, and routes it through the rule lists with
/// `YAMLConfig.enableRule(_:kind:)` — `only_rules` when the file has one, otherwise
/// `opt_in_rules` / `analyzer_rules` — so the mirror stays a file SwiftLint accepts. That
/// routing reads the rule's deprecated names as the rule, as SwiftLint does, so
/// `disabled_rules: [variable_name]` stops holding `identifier_name` off.
/// Preserves the config's `included:`/`excluded:` as loaded — relative paths resolve the same in
/// the mirror, and loading writes the rest to name their place there (see
/// `SimulationWorkspaceBuilder.mirrorExclusions(in:pulledIn:plan:)`).
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
        config.enableRule(ruleId, kind: RuleListKind(isOptIn: isOptIn, isAnalyzer: isAnalyzer))
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
/// enable a rule as Enable does — in the root config — while still honoring nested
/// configs, which go on disabling or relaxing it beneath them, the configs must live at
/// their real relative locations on disk — but we must not mutate the user's tree. So we
/// mirror the workspace: `.swift` sources are hardlinked (copied only on a cross-volume
/// fallback), the root config is reproduced with the target rule enabled, and every
/// other `.swiftlint.yml` as it is. SwiftLint then lints the mirror in its normal
/// (`.effective`) mode.
/// What `ImpactSimulator` needs from a workspace builder.
///
/// Every other collaborator in `ImpactSimulator.init` is a seam — `SwiftLintCLIProtocol`,
/// `DateProvider`, `IDProvider` — and this one was constructed inside the initializer from the
/// `FileManager` it was handed. `concrete-type-usage` reported the odd one out.
///
/// Its nominal seam was that `FileManager`, which is close to unfakeable: there is no useful way to
/// hand in a `FileManager` that does not touch a real file system. So simulating a rule meant
/// mirroring a whole workspace into a temp directory before any of `ImpactSimulator`'s own logic —
/// the diffing, the durations, the identifiers — could be reached.
protocol SimulationWorkspaceBuilding: Sendable {

    /// Mirrors `workspace` into a fresh location and returns a workspace ready for `applyRule`.
    func makeWorkspace(for workspace: Workspace, baseConfigPath: URL?) async throws -> SimulationWorkspace
}

struct SimulationWorkspaceBuilder: SimulationWorkspaceBuilding {

    let fileManager: FileManager
    /// See ``MirrorLinkDiscovery/outsideEntryLimit``; lowered in tests.
    private let outsideEntryLimit: Int

    init(fileManager: FileManager = .default, outsideEntryLimit: Int = MirrorLinkDiscovery.outsideEntryLimit) {
        self.fileManager = fileManager
        self.outsideEntryLimit = outsideEntryLimit
    }

    /// Mirrors `workspace` into a fresh temp directory and returns a
    /// ``SimulationWorkspace`` ready for ``SimulationWorkspace/applyRule(_:isOptIn:isAnalyzer:parameterOverrides:)``.
    ///
    /// The walking and copying run off the main actor, stop when the calling task is
    /// cancelled, and refuse links that lead to more outside the workspace than the mirror will
    /// copy (``MirrorTooLargeError``); a failure leaves no container behind.
    ///
    /// - Parameter baseConfigPath: A config to seed the root from when the
    ///   workspace has no root `.swiftlint.yml` of its own. Nested configs are
    ///   always discovered from the workspace tree regardless.
    func makeWorkspace(for workspace: Workspace, baseConfigPath: URL?) async throws -> SimulationWorkspace {
        let rootConfig = rootConfigFile(for: workspace, baseConfigPath: baseConfigPath)
        let mirrored = try await Self.mirrorOffMainActor(
            workspace.path,
            rootConfig: rootConfig,
            limit: outsideEntryLimit
        )
        return try finish(mirrored, for: workspace, baseConfigPath: baseConfigPath)
    }

    /// ``makeWorkspace(for:baseConfigPath:)``, synchronously on the caller's thread.
    func makeWorkspace(for workspace: Workspace, baseConfigPath: URL?) throws -> SimulationWorkspace {
        let rootConfig = rootConfigFile(for: workspace, baseConfigPath: baseConfigPath)
        let mirrored = try Self.mirror(
            workspace.path,
            rootConfig: rootConfig,
            limit: outsideEntryLimit,
            fileManager: fileManager
        )
        return try finish(mirrored, for: workspace, baseConfigPath: baseConfigPath)
    }

    // MARK: - Mirroring

    /// The config the mirror's root gets: the workspace's own, or else the seed.
    func rootConfigFile(for workspace: Workspace, baseConfigPath: URL?) -> URL? {
        let own = workspace.path.appendingPathComponent(ConfigTreeDiscovery.configFileName)
        if fileManager.fileExists(atPath: own.path) { return own }
        let seeds = [baseConfigPath, workspace.configPath].compactMap(\.self)
        return seeds.first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Reads the mirror's configs; a failure removes the mirror.
    private func finish(
        _ mirrored: Mirrored,
        for workspace: Workspace,
        baseConfigPath: URL?
    ) throws -> SimulationWorkspace {
        let loaded: LoadedConfigs
        do {
            loaded = try loadConfigs(of: mirrored.plan, for: workspace, baseConfigPath: baseConfigPath)
        } catch {
            try? fileManager.removeItem(at: mirrored.container)
            mirrored.lock.release()
            throw error
        }
        return SimulationWorkspace(
            root: mirrored.root,
            configs: loaded.entries,
            fileManager: fileManager,
            container: mirrored.container,
            externalFolders: mirrored.plan.externalFolders,
            lock: mirrored.lock,
            rootInContainer: mirrored.plan.lintRoot,
            customRuleIds: loaded.customRuleIds,
            workspaceRoot: mirrored.workspaceRoot
        )
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
