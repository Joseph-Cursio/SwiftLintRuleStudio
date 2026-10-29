//
//  ResolvedConfigurationEngine.swift
//  SwiftLintRuleStudio
//
//  Computes the effective merged SwiftLint configuration for a folder by walking
//  its layer chain (root → … → folder) and applying SwiftLint's non-uniform
//  nested-merge semantics, attributing each decision to the layer that set it.
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
    /// The layer chain is every config whose governed directory is an ancestor of
    /// (or equal to) `targetDirectory`, ordered root → deepest. Configs that
    /// failed to parse are skipped (they contribute nothing) rather than aborting
    /// the merge.
    public func resolve(at targetDirectory: URL, in tree: ConfigTree) -> ResolvedConfiguration {
        let chain = Self.layerChain(for: targetDirectory, in: tree)
        var accumulator = Accumulator()
        for discovered in chain {
            guard let config = discovered.config else { continue }
            Self.merge(
                config: config,
                layer: ConfigLayer(discovered),
                isRoot: discovered.isRoot,
                into: &accumulator
            )
        }
        return accumulator.resolved(
            targetDirectory: targetDirectory,
            layerChain: chain.map(ConfigLayer.init)
        )
    }

    /// Convenience: resolve the configuration that applies to a single file.
    public func resolve(forFile fileURL: URL, in tree: ConfigTree) -> ResolvedConfiguration {
        resolve(at: fileURL.deletingLastPathComponent(), in: tree)
    }

    // MARK: - Layer chain

    /// The configs that apply to `targetDirectory`, ordered root → deepest.
    nonisolated static func layerChain(for targetDirectory: URL, in tree: ConfigTree) -> [DiscoveredConfig] {
        let targetComponents = targetDirectory.standardizedFileURL.pathComponents
        let applicable = tree.configs.filter { config in
            let directoryComponents = config.directoryPath.standardizedFileURL.pathComponents
            guard directoryComponents.count <= targetComponents.count else { return false }
            return Array(targetComponents.prefix(directoryComponents.count)) == directoryComponents
        }
        return applicable.sorted { $0.depth < $1.depth }
    }

    // MARK: - Merge

    /// Mutable state threaded through the layer chain.
    private struct Accumulator {
        var disabled = AttributedSet()
        var optIn = AttributedSet()
        var analyzer = AttributedSet()
        var onlyRules: AttributedValue<[String]>?
        var ruleConfigurations: [String: ResolvedRuleConfiguration] = [:]
        var excluded: AttributedValue<[String]>?
        var included: AttributedValue<[String]>?
        var reporter: AttributedValue<String>?

        func resolved(targetDirectory: URL, layerChain: [ConfigLayer]) -> ResolvedConfiguration {
            ResolvedConfiguration(
                targetDirectory: targetDirectory,
                layerChain: layerChain,
                disabledRules: disabled.decisions(),
                optInRules: optIn.decisions(),
                analyzerRules: analyzer.decisions(),
                onlyRules: onlyRules,
                ruleConfigurations: ruleConfigurations.values.sorted { $0.identifier < $1.identifier },
                excluded: excluded,
                included: included,
                reporter: reporter
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

    private static func merge(
        config: YAMLConfig,
        layer: ConfigLayer,
        isRoot: Bool,
        into accumulator: inout Accumulator
    ) {
        mergeMembership(config: config, layer: layer, into: &accumulator)
        mergeRuleConfigurations(config: config, layer: layer, into: &accumulator)
        if let only = config.onlyRules {
            let rules = Set(only.map(SwiftLintDeprecations.currentName(of:)))
            accumulator.onlyRules = AttributedValue(value: rules.sorted(), setBy: layer)
        }
        if isRoot {
            mergeRootOnlyKeys(config: config, layer: layer, into: &accumulator)
        }
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
    private static func mergeMembership(
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        let currentNames = { (rules: [String]?) in (rules ?? []).map(SwiftLintDeprecations.currentName(of:)) }
        let childDisabled = currentNames(config.disabledRules)
        let disabledHere = Set(childDisabled)
        let childOptIn = currentNames(config.optInRules).filter { !disabledHere.contains($0) }

        for rule in childOptIn { accumulator.disabled.remove(rule) }
        for rule in childDisabled { accumulator.optIn.remove(rule) }
        for rule in childDisabled { accumulator.disabled.insert(rule, setBy: layer) }
        for rule in childOptIn { accumulator.optIn.insert(rule, setBy: layer) }
        for rule in currentNames(config.analyzerRules) { accumulator.analyzer.insert(rule, setBy: layer) }
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

    /// excluded / included / reporter are honored only from the root config;
    /// SwiftLint ignores nested values for these keys.
    private static func mergeRootOnlyKeys(
        config: YAMLConfig,
        layer: ConfigLayer,
        into accumulator: inout Accumulator
    ) {
        if let exclusions = config.excluded, !exclusions.isEmpty {
            accumulator.excluded = AttributedValue(value: exclusions, setBy: layer)
        }
        if let inclusions = config.included, !inclusions.isEmpty {
            accumulator.included = AttributedValue(value: inclusions, setBy: layer)
        }
        if let reporterName = config.reporter {
            accumulator.reporter = AttributedValue(value: reporterName, setBy: layer)
        }
    }
}
