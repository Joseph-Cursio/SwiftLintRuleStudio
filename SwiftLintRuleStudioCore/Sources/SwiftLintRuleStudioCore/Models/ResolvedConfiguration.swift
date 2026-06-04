//
//  ResolvedConfiguration.swift
//  SwiftLintRuleStudio
//
//  The effective, merged SwiftLint configuration that applies to a particular
//  folder — with each decision attributed to the config layer that set it.
//  This is the model the resolved-config inspector renders. The merge follows
//  SwiftLint's *non-uniform* nested semantics (see docs/nested-config-visibility.md):
//  rule configs override, disabled/opt-in accumulate, only_rules hard-resets,
//  and excluded/included/reporter come from the root config alone.
//

import Foundation

/// Identifies a single config layer (`.swiftlint.yml`) that contributed to a
/// resolved configuration — the "Set by" attribution in the inspector.
public struct ConfigLayer: Identifiable, Sendable {
    /// Matches the originating ``DiscoveredConfig/id``.
    nonisolated public let id: UUID
    /// Path relative to the workspace root, e.g. `Tests/.swiftlint.yml`.
    nonisolated public let relativePath: String
    /// Directory depth below the workspace root (root layer is `0`).
    nonisolated public let depth: Int
    /// Whether this is the workspace root layer.
    nonisolated public let isRoot: Bool
    /// Short label for the UI — `root`, or the governed directory name (`Tests`).
    nonisolated public let displayName: String

    nonisolated public init(
        id: UUID,
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
            displayName: config.isRoot ? "root" : config.directoryPath.lastPathComponent
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
    nonisolated public let identifier: String
    nonisolated public let setBy: ConfigLayer

    nonisolated public init(identifier: String, setBy: ConfigLayer) {
        self.identifier = identifier
        self.setBy = setBy
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
/// chain (root → … → folder).
public struct ResolvedConfiguration: Sendable {
    /// The folder this configuration was resolved for.
    nonisolated public let targetDirectory: URL
    /// The layers that applied, ordered root → deepest.
    nonisolated public let layerChain: [ConfigLayer]
    /// Effective `disabled_rules`, each attributed to the layer that disabled it.
    nonisolated public let disabledRules: [ResolvedRuleDecision]
    /// Effective `opt_in_rules`, each attributed to the layer that opted it in.
    nonisolated public let optInRules: [ResolvedRuleDecision]
    /// Effective `analyzer_rules`, each attributed to the layer that added it.
    nonisolated public let analyzerRules: [ResolvedRuleDecision]
    /// The `only_rules` whitelist, if any layer declares one. When present, only
    /// these rules run in this subtree (a hard reset); `setBy` is the deepest
    /// declaring layer.
    nonisolated public let onlyRules: AttributedValue<[String]>?
    /// Per-rule configurations (severity/params), each with override history.
    nonisolated public let ruleConfigurations: [ResolvedRuleConfiguration]
    /// `excluded:` — honored only from the root config.
    nonisolated public let excluded: AttributedValue<[String]>?
    /// `included:` — honored only from the root config.
    nonisolated public let included: AttributedValue<[String]>?
    /// `reporter:` — honored only from the root config.
    nonisolated public let reporter: AttributedValue<String>?

    nonisolated public init(
        targetDirectory: URL,
        layerChain: [ConfigLayer],
        disabledRules: [ResolvedRuleDecision],
        optInRules: [ResolvedRuleDecision],
        analyzerRules: [ResolvedRuleDecision],
        onlyRules: AttributedValue<[String]>?,
        ruleConfigurations: [ResolvedRuleConfiguration],
        excluded: AttributedValue<[String]>?,
        included: AttributedValue<[String]>?,
        reporter: AttributedValue<String>?
    ) {
        self.targetDirectory = targetDirectory
        self.layerChain = layerChain
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
