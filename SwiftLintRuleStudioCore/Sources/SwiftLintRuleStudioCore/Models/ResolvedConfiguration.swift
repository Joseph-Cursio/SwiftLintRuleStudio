//
//  ResolvedConfiguration.swift
//  SwiftLintRuleStudio
//
//  The effective, merged SwiftLint configuration that applies to a particular
//  folder — with each decision attributed to the config layer that set it.
//  This is the model the resolved-config inspector renders. SwiftLint merges the
//  root config with the nearest nested config alone, and the merge follows its
//  *non-uniform* semantics (see docs/nested-config-visibility.md): rule configs
//  override, disabled/opt-in accumulate, only_rules hard-resets (and a deeper
//  layer's disabled/opt-in then edit that whitelist), and
//  excluded/included/reporter come from the root config and the configs it
//  pulls in alone.
//

import Foundation

/// Identifies a single config layer (`.swiftlint.yml`) that contributed to a
/// resolved configuration — the "Set by" attribution in the inspector.
public struct ConfigLayer: Identifiable, Sendable {
    /// Matches the originating ``DiscoveredConfig/id`` — the config file's path.
    nonisolated public let id: URL
    /// Path relative to the workspace root, e.g. `Tests/.swiftlint.yml`, or
    /// `../../.swiftlint.yml` for a config the root pulls in from outside it; a
    /// remote config's URL.
    nonisolated public let relativePath: String
    /// Directory depth below the workspace root (root layer is `0`).
    nonisolated public let depth: Int
    /// Whether this is the workspace root layer.
    nonisolated public let isRoot: Bool
    /// Short label for the UI — `root`, the governed directory name (`Tests`), or
    /// the path or URL of a config the root pulls in from elsewhere (see
    /// ``DiscoveredConfig/displayName``).
    nonisolated public let displayName: String

    nonisolated public init(
        id: URL,
        relativePath: String,
        depth: Int,
        isRoot: Bool,
        displayName: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.depth = depth
        self.isRoot = isRoot
        self.displayName = displayName
    }

    /// Builds a layer descriptor from a discovered config.
    nonisolated public init(_ config: DiscoveredConfig) {
        self.init(
            id: config.id,
            relativePath: config.relativePath,
            depth: config.depth,
            isRoot: config.isRoot,
            displayName: config.displayName
        )
    }
}

/// A value taken from a single layer, paired with the layer that set it.
public struct AttributedValue<Value: Sendable>: Sendable {
    nonisolated public let value: Value
    nonisolated public let setBy: ConfigLayer

    nonisolated public init(value: Value, setBy: ConfigLayer) {
        self.value = value
        self.setBy = setBy
    }
}

/// A rule's membership in an accumulated set (`disabled_rules`, `opt_in_rules`,
/// `analyzer_rules`), attributed to the layer that last set it.
public struct ResolvedRuleDecision: Sendable {
    /// The rule's current name, also where a config listed it under a deprecated
    /// alias (`variable_name` for `identifier_name`), as SwiftLint reads the lists.
    nonisolated public let identifier: String
    nonisolated public let setBy: ConfigLayer

    nonisolated public init(identifier: String, setBy: ConfigLayer) {
        self.identifier = identifier
        self.setBy = setBy
    }
}

/// The `only_rules` whitelist in effect for a folder, with each rule attributed to
/// the layer that put it there.
///
/// The deepest layer that declares `only_rules` starts the whitelist with its
/// `only_rules` and `analyzer_rules`. A deeper layer without `only_rules` edits it,
/// as SwiftLint merges a child in default mode beneath an only-mode parent: the
/// child's `opt_in_rules` and `analyzer_rules` join, and its `disabled_rules` leave.
public struct ResolvedOnlyRules: Sendable {
    /// The deepest layer that declares `only_rules`.
    nonisolated public let declaredBy: ConfigLayer
    /// The rules that run, sorted, each under its current name and attributed to the
    /// layer that last added it.
    nonisolated public let rules: [ResolvedRuleDecision]

    nonisolated public init(declaredBy: ConfigLayer, rules: [ResolvedRuleDecision]) {
        self.declaredBy = declaredBy
        self.rules = rules
    }

    /// The identifiers of the rules that run, sorted.
    nonisolated public var identifiers: [String] { rules.map(\.identifier) }

    /// Whether `ruleIdentifier` runs.
    nonisolated public func contains(_ ruleIdentifier: String) -> Bool {
        rules.contains { $0.identifier == ruleIdentifier }
    }
}

/// A rule's resolved configuration (severity/parameters), the layer that set it,
/// and the value it overrode — so the inspector can show "was ⚠️ 120 → 200".
public struct ResolvedRuleConfiguration: Sendable {
    nonisolated public let identifier: String
    nonisolated public let configuration: RuleConfiguration
    nonisolated public let setBy: ConfigLayer
    /// The configuration this one overrode (from a shallower layer), if any.
    nonisolated public let previousConfiguration: RuleConfiguration?
    /// The layer the overridden configuration came from, if any.
    nonisolated public let previousSetBy: ConfigLayer?

    nonisolated public init(
        identifier: String,
        configuration: RuleConfiguration,
        setBy: ConfigLayer,
        previousConfiguration: RuleConfiguration?,
        previousSetBy: ConfigLayer?
    ) {
        self.identifier = identifier
        self.configuration = configuration
        self.setBy = setBy
        self.previousConfiguration = previousConfiguration
        self.previousSetBy = previousSetBy
    }

    /// Whether this rule's configuration overrode a shallower layer's value.
    nonisolated public var overridesAncestor: Bool { previousConfiguration != nil }
}

/// The effective configuration that applies to a folder, merged from its layer
/// chain: the root config with the configs it pulls in, then the nearest nested
/// config at or above the folder.
public struct ResolvedConfiguration: Sendable {
    /// The folder this configuration was resolved for.
    nonisolated public let targetDirectory: URL
    /// The layers that applied, in the order they merged: the root config with the
    /// configs it pulls in with `parent_config`/`child_config` (the furthest parent
    /// first), then the nearest nested config at or above the folder. Any of them
    /// may be absent.
    nonisolated public let layerChain: [ConfigLayer]
    /// The nested configs above the nearest one, ordered root → deepest: their
    /// folders hold `targetDirectory`, but SwiftLint merges the root config with
    /// the nearest nested config alone, so none of them applies here. A config the
    /// root pulls in is never among them: it is part of the root's settings.
    nonisolated public let skippedLayers: [ConfigLayer]
    /// Effective `disabled_rules`, each attributed to the layer that disabled it.
    nonisolated public let disabledRules: [ResolvedRuleDecision]
    /// Effective `opt_in_rules`, each attributed to the layer that opted it in.
    nonisolated public let optInRules: [ResolvedRuleDecision]
    /// Effective `analyzer_rules`, each attributed to the layer that added it.
    nonisolated public let analyzerRules: [ResolvedRuleDecision]
    /// The `only_rules` whitelist, if any layer declares one. When present, only
    /// these rules run here, and ``disabledRules``, ``optInRules`` and
    /// ``analyzerRules`` hold only the decisions of the declaring layer and the
    /// layers beneath it: those above it no longer decide anything.
    nonisolated public let onlyRules: ResolvedOnlyRules?
    /// Per-rule configurations (severity/params), each with override history.
    nonisolated public let ruleConfigurations: [ResolvedRuleConfiguration]
    /// `excluded:` of the root configuration: the entries of the root config and of
    /// the configs it pulls in, merged as SwiftLint merges them, each attributed to
    /// the config that wrote it. SwiftLint reads an entry relative to that config's
    /// folder, so each is given as a path from the workspace (`../../Pods` for
    /// `Pods` in `../../.swiftlint.yml`); an absolute entry, as written. A nested
    /// config's are ignored, as SwiftLint ignores them. Empty when nothing is
    /// excluded.
    nonisolated public let excluded: [AttributedValue<String>]
    /// `included:` of the root configuration, read as ``excluded`` is.
    nonisolated public let included: [AttributedValue<String>]
    /// `reporter:` — SwiftLint takes it from the first config of the root
    /// configuration alone: the root's furthest `parent_config`, or the root
    /// config. `nil` where that config sets none, for SwiftLint's default.
    nonisolated public let reporter: AttributedValue<String>?

    nonisolated public init(
        targetDirectory: URL,
        layerChain: [ConfigLayer],
        skippedLayers: [ConfigLayer],
        disabledRules: [ResolvedRuleDecision],
        optInRules: [ResolvedRuleDecision],
        analyzerRules: [ResolvedRuleDecision],
        onlyRules: ResolvedOnlyRules?,
        ruleConfigurations: [ResolvedRuleConfiguration],
        excluded: [AttributedValue<String>],
        included: [AttributedValue<String>],
        reporter: AttributedValue<String>?
    ) {
        self.targetDirectory = targetDirectory
        self.layerChain = layerChain
        self.skippedLayers = skippedLayers
        self.disabledRules = disabledRules
        self.optInRules = optInRules
        self.analyzerRules = analyzerRules
        self.onlyRules = onlyRules
        self.ruleConfigurations = ruleConfigurations
        self.excluded = excluded
        self.included = included
        self.reporter = reporter
    }

    /// Whether an `only_rules` whitelist is in effect for this subtree.
    nonisolated public var isOnlyRulesMode: Bool { onlyRules != nil }

    /// The resolved configuration for a specific rule, if any layer set one.
    nonisolated public func configuration(for ruleIdentifier: String) -> ResolvedRuleConfiguration? {
        ruleConfigurations.first { $0.identifier == ruleIdentifier }
    }

    /// The layer that disabled `ruleIdentifier`, if it is disabled.
    nonisolated public func disablingLayer(for ruleIdentifier: String) -> ConfigLayer? {
        disabledRules.first { $0.identifier == ruleIdentifier }?.setBy
    }
}
