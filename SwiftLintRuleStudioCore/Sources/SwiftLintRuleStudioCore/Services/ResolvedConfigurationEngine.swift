//
//  ResolvedConfigurationEngine.swift
//  SwiftLintRuleStudio
//
//  Computes the effective merged SwiftLint configuration for a folder from its
//  layer chain — the root config with the configs it pulls in, then the nearest
//  nested config at or above the folder, as SwiftLint picks them — applying
//  SwiftLint's non-uniform merge semantics and attributing each decision to the
//  layer that set it.
//
//  ⚠️ These merge rules drift across SwiftLint versions. This reimplementation
//  drives the UI (it is fast and attributable); it must be reconciled against an
//  actual lint of the subtree before being trusted as ground truth — see the
//  "SwiftLint as oracle" note in docs/nested-config-visibility.md.
//

import Foundation

/// Resolves the effective configuration for a folder from a ``ConfigTree``.
public struct ResolvedConfigurationEngine {
    /// Creates a resolver.
    nonisolated public init() {}

    /// Resolves the effective configuration that applies to `targetDirectory`.
    ///
    /// The layer chain is the root config with the configs it pulls in, then the
    /// nearest nested config at or above `targetDirectory` (see
    /// ``layerChain(for:in:)``); the other configs above it are reported as
    /// skipped. Configs that failed to parse contribute nothing rather than
    /// aborting the merge.
    ///
    /// `excluded`, `included` and `reporter` are read from the root configuration
    /// alone — the root config and the configs it pulls in — as SwiftLint reads
    /// them (see ``mergeRootConfigurationKeys(config:of:layer:workspaceRoot:into:)``).
    public func resolve(at targetDirectory: URL, in tree: ConfigTree) -> ResolvedConfiguration {
        let ancestors = Self.ancestorConfigs(of: targetDirectory, in: tree)
        let chain = Self.layerChain(among: ancestors, in: tree)
        let chainIDs = Set(chain.map(\.id))
        var accumulator = Accumulator()
        for discovered in chain {
            guard let config = discovered.config else { continue }
            let layer = ConfigLayer(discovered)
            Self.merge(config: config, layer: layer, into: &accumulator)
            if discovered.isRoot || discovered.rootGraphPosition != nil {
                Self.mergeRootConfigurationKeys(
                    config: config,
                    of: discovered,
                    layer: layer,
                    workspaceRoot: tree.workspaceRoot,
                    into: &accumulator
                )
            }
        }
        // SwiftLint keeps the reporter of the first config it builds the root
        // configuration from, its default where that config names none.
        if let first = tree.rootGraph.first, let reporterName = first.config?.reporter {
            accumulator.reporter = AttributedValue(value: reporterName, setBy: ConfigLayer(first))
        }
        return accumulator.resolved(
            targetDirectory: targetDirectory,
            layerChain: chain.map(ConfigLayer.init),
            skippedLayers: ancestors.filter { !chainIDs.contains($0.id) }.map(ConfigLayer.init)
        )
    }

    /// Convenience: resolve the configuration that applies to a single file.
    public func resolve(forFile fileURL: URL, in tree: ConfigTree) -> ResolvedConfiguration {
        resolve(at: fileURL.deletingLastPathComponent(), in: tree)
    }

    // MARK: - Layer chain

    /// The configs SwiftLint applies to `targetDirectory`: the root config with
    /// the configs it pulls in (``ConfigTree/rootGraph``), then the nearest nested
    /// config at or above the folder.
    ///
    /// SwiftLint's `configuration(forDirectory:)` walks up from a file's folder and
    /// merges the root configuration with the first nested `.swiftlint.yml` it
    /// meets, and with no other: a config in a folder between that one and the
    /// root does not apply. With `Sub/.swiftlint.yml` disabling `empty_count` and a
    /// `Sub/Deeper/.swiftlint.yml` beneath it, a file in `Sub/Deeper` runs the
    /// `empty_count` the root opts in. SwiftLint picks the nearest config by its
    /// presence alone, so one that failed to parse here still stands in for those
    /// above it, and contributes nothing.
    ///
    /// The configs the root pulls in with `parent_config` and `child_config` are
    /// part of the root configuration, so they apply in every folder, in the
    /// order SwiftLint merges them. Its search for the nearest config passes over
    /// them: with the root's `child_config: Sub/.swiftlint.yml`, a file in
    /// `Sub/Deeper` beside its own config gets `Sub`'s settings as part of the
    /// root's, and those of `Sub/Deeper` on top.
    nonisolated static func layerChain(for targetDirectory: URL, in tree: ConfigTree) -> [DiscoveredConfig] {
        layerChain(among: ancestorConfigs(of: targetDirectory, in: tree), in: tree)
    }

    /// Every config whose governed directory is `targetDirectory` or one of its
    /// ancestors, ordered root → deepest.
    nonisolated static func ancestorConfigs(of targetDirectory: URL, in tree: ConfigTree) -> [DiscoveredConfig] {
        let targetComponents = targetDirectory.standardizedFileURL.pathComponents
        let ancestors = tree.configs.filter { config in
            let directoryComponents = config.directoryPath.standardizedFileURL.pathComponents
            guard directoryComponents.count <= targetComponents.count else { return false }
            return Array(targetComponents.prefix(directoryComponents.count)) == directoryComponents
        }
        return ancestors.sorted { $0.depth < $1.depth }
    }

    /// The tree's root graph, then the deepest of `ancestors` outside it, from
    /// `ancestors` ordered root → deepest.
    nonisolated private static func layerChain(
        among ancestors: [DiscoveredConfig],
        in tree: ConfigTree
    ) -> [DiscoveredConfig] {
        let nearest = ancestors.last { !$0.isRoot && $0.rootGraphPosition == nil }
        return tree.rootGraph + (nearest.map { [$0] } ?? [])
    }

    // MARK: - Merge

    /// Mutable state threaded through the layer chain.
    private struct Accumulator {
        var disabled = AttributedSet()
        var optIn = AttributedSet()
        var analyzer = AttributedSet()
        var only: OnlyRules?
        var ruleConfigurations: [String: ResolvedRuleConfiguration] = [:]
        var excluded: [PathEntry] = []
        var included: [PathEntry] = []
        var reporter: AttributedValue<String>?

        func resolved(
            targetDirectory: URL,
            layerChain: [ConfigLayer],
            skippedLayers: [ConfigLayer]
        ) -> ResolvedConfiguration {
            ResolvedConfiguration(
                targetDirectory: targetDirectory,
                layerChain: layerChain,
                skippedLayers: skippedLayers,
                disabledRules: disabled.decisions(),
                optInRules: optIn.decisions(),
                analyzerRules: analyzer.decisions(),
                onlyRules: only.map { ResolvedOnlyRules(declaredBy: $0.declaredBy, rules: $0.rules.decisions()) },
                ruleConfigurations: ruleConfigurations.values.sorted { $0.identifier < $1.identifier },
                excluded: excluded.map(\.entry),
                included: included.map(\.entry),
                reporter: reporter
            )
        }
    }

    /// An `excluded`/`included` entry: as the resolved configuration shows it, and
    /// the path SwiftLint compares it by.
    private struct PathEntry {
        let entry: AttributedValue<String>
        /// Absolute and standardized, with the entry's trailing `/` kept: SwiftLint
        /// compares entries as URLs, which tell `Pods/` from `Pods`.
        let path: String

        init(written: String, folder: URL, layer: ConfigLayer, workspaceRoot: URL) {
            let isAbsolute = written.hasPrefix("/")
            // The folder is standardized before the entry joins it: that drops a
            // `/private` the file walk spells and the workspace's path may not, which
            // standardizing does only for a path that exists.
            let url = isAbsolute
                ? URL(fileURLWithPath: written)
                : folder.standardizedFileURL.appendingPathComponent(written)
            let trailing = written.hasSuffix("/") ? "/" : ""
            path = url.standardizedFileURL.path + trailing
            entry = AttributedValue(
                value: isAbsolute ? written : ConfigTreeDiscovery.path(of: url, from: workspaceRoot),
                setBy: layer
            )
        }
    }

    /// A rule set with per-rule attribution to the layer that last set it.
    private struct AttributedSet {
        private var members: Set<String> = []
        private var attribution: [String: ConfigLayer] = [:]

        mutating func insert(_ rule: String, setBy layer: ConfigLayer) {
            members.insert(rule)
            attribution[rule] = layer
        }

        mutating func remove(_ rule: String) {
            members.remove(rule)
            attribution[rule] = nil
        }

        func decisions() -> [ResolvedRuleDecision] {
            members.sorted().compactMap { rule in
                attribution[rule].map { ResolvedRuleDecision(identifier: rule, setBy: $0) }
            }
        }
    }

    /// The `only_rules` whitelist, from the deepest layer that declares one on.
    private struct OnlyRules {
        let declaredBy: ConfigLayer
        var rules = AttributedSet()
    }

    private static func merge(
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        // An empty `only_rules` is no list (``YAMLConfig/usesOnlyRules``): SwiftLint
        // stays in default mode, and beneath a parent's list keeps the parent's.
        if let only = config.onlyRules, !only.isEmpty {
            declareOnlyRules(only, config: config, layer: layer, into: &accumulator)
        } else {
            mergeMembership(config: config, layer: layer, into: &accumulator)
        }
        mergeRuleConfigurations(config: config, layer: layer, into: &accumulator)
    }

    /// disabled_rules / opt_in_rules accumulate symmetrically (opting a rule in
    /// removes it from disabled and vice versa); analyzer_rules accumulate.
    ///
    /// A single config that lists the same rule in *both* keys is contradicting
    /// itself, and SwiftLint resolves that in favour of `disabled_rules` — the
    /// rule does not run. Verified against SwiftLint 0.65.0: with a config naming
    /// `force_unwrapping` in both keys the rule stays silent on code that
    /// violates it, while the same file under `opt_in_rules` alone reports it;
    /// a default rule (`todo`) behaves the same way. No warning is emitted, so
    /// the contradiction is resolved silently rather than rejected. Dropping the
    /// opt-in side up front is what keeps a rule from landing in both resolved
    /// sets — the mutual-exclusion invariant the property laws pin.
    ///
    /// SwiftLint maps each config's lists through the rules' aliases before it
    /// merges them (`RulesMode.applied(aliasResolver:)`), so a layer can opt in or
    /// disable a rule under either name. Every entry is read the same way here,
    /// and each rule is one decision, under its current name, however it was
    /// written: `disabled_rules: [if_let_shadowing]` beneath a parent's
    /// `opt_in_rules: [shorthand_optional_binding]` turns that rule off.
    ///
    /// Beneath a layer that declares `only_rules`, the same lists edit the
    /// whitelist instead, as SwiftLint merges a child in default mode beneath an
    /// only-mode parent (`RulesWrapper.mergeDefaultMode`): the whitelist becomes
    /// `(childOptIn ∪ childAnalyzer ∪ parentOnly) − childDisabled`. SwiftLint
    /// reads a config's `analyzer_rules` as opt-ins (`RulesMode.init`), so they
    /// join the whitelist too, unless the same layer disables them.
    private static func mergeMembership(
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        let childDisabled = currentNames(config.disabledRules)
        let disabledHere = Set(childDisabled)
        let childOptIn = currentNames(config.optInRules).filter { !disabledHere.contains($0) }
        let childAnalyzer = currentNames(config.analyzerRules)

        for rule in childOptIn { accumulator.disabled.remove(rule) }
        for rule in childDisabled { accumulator.optIn.remove(rule) }
        for rule in childDisabled { accumulator.disabled.insert(rule, setBy: layer) }
        for rule in childOptIn { accumulator.optIn.insert(rule, setBy: layer) }
        for rule in childAnalyzer { accumulator.analyzer.insert(rule, setBy: layer) }

        if var only = accumulator.only {
            for rule in childDisabled { only.rules.remove(rule) }
            for rule in childOptIn + childAnalyzer where !disabledHere.contains(rule) {
                only.rules.insert(rule, setBy: layer)
            }
            accumulator.only = only
        }
    }

    /// A layer that declares `only_rules` starts a new whitelist: SwiftLint reads
    /// that config in only mode, and a child's whitelist replaces its parent's
    /// (`RulesWrapper.merged(with:)`). Its `analyzer_rules` join the whitelist, as
    /// `RulesMode.init` folds them in. The membership decisions of the layers above
    /// it no longer decide anything, so they are dropped.
    ///
    /// SwiftLint refuses `disabled_rules` or `opt_in_rules` beside `only_rules`
    /// (the configuration validator flags it), so this layer's own are not read.
    private static func declareOnlyRules(
        _ onlyRules: [String],
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        let analyzerRules = currentNames(config.analyzerRules)
        var only = OnlyRules(declaredBy: layer)
        for rule in currentNames(onlyRules) + analyzerRules { only.rules.insert(rule, setBy: layer) }
        accumulator.only = only
        accumulator.disabled = AttributedSet()
        accumulator.optIn = AttributedSet()
        accumulator.analyzer = AttributedSet()
        for rule in analyzerRules { accumulator.analyzer.insert(rule, setBy: layer) }
    }

    /// A rule list read the way SwiftLint reads it: each entry under the current
    /// name of the rule it names.
    private static func currentNames(_ rules: [String]?) -> [String] {
        (rules ?? []).map(SwiftLintDeprecations.currentName(of:))
    }

    /// Rule configuration (severity/params): a deeper layer overrides a shallower
    /// one; the overridden value is kept for "was …" diffs.
    ///
    /// SwiftLint applies a configuration keyed by an alias to the rule itself, so
    /// a child's `identifier_name:` overrides its parent's `variable_name:`. It
    /// refuses a file that configures one rule under both names; here the entry
    /// under the current name is kept.
    private static func mergeRuleConfigurations(
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        for (ruleIdentifier, ruleConfiguration) in config.rules {
            let rule = SwiftLintDeprecations.currentName(of: ruleIdentifier)
            if rule != ruleIdentifier, config.rules[rule] != nil { continue }
            let prior = accumulator.ruleConfigurations[rule]
            accumulator.ruleConfigurations[rule] = ResolvedRuleConfiguration(
                identifier: rule,
                configuration: ruleConfiguration,
                setBy: layer,
                previousConfiguration: prior?.configuration,
                previousSetBy: prior?.setBy
            )
        }
    }

    /// `excluded` and `included`, which SwiftLint reads from the root
    /// configuration alone: a nested config's have no effect on which files it
    /// lints.
    ///
    /// SwiftLint merges each config of the root's chain onto those before it
    /// (`Configuration.merged(withChild:)`), the furthest parent first: a config's
    /// `excluded` entries drop the `included` entries before it that name the same
    /// path, its `included` entries drop such `excluded` entries, and then its own
    /// are added. So a parent's exclusion of a folder its child includes keeps
    /// nothing out. Each entry is read relative to the folder of the config that
    /// writes it — a remote config's, the folder of the config that pulled it in.
    private static func mergeRootConfigurationKeys(
        config: YAMLConfig,
        of discovered: DiscoveredConfig,
        layer: ConfigLayer,
        workspaceRoot: URL,
        into accumulator: inout Accumulator
    ) {
        func entries(_ written: [String]?) -> [PathEntry] {
            (written ?? []).map {
                PathEntry(written: $0, folder: discovered.directoryPath, layer: layer, workspaceRoot: workspaceRoot)
            }
        }
        let included = entries(config.included)
        let excluded = entries(config.excluded)
        let includedPaths = Set(included.map(\.path))
        let excludedPaths = Set(excluded.map(\.path))
        accumulator.included = accumulator.included.filter { !excludedPaths.contains($0.path) } + included
        accumulator.excluded = accumulator.excluded.filter { !includedPaths.contains($0.path) } + excluded
    }
}
