//
//  ConfigMapDisplay.swift
//  SwiftLintRuleStudio
//
//  Display models for the Config Map UI — the sparse config tree and the
//  per-folder resolved-config inspector. These are produced by ConfigMapPresenter
//  from a ConfigTree / ResolvedConfiguration so the SwiftUI layer stays thin and
//  the presentation logic stays unit-testable in the Core package.
//

import Foundation

/// A row in the sparse Config Tree (one per config-bearing folder).
public struct ConfigTreeRow: Identifiable, Sendable {
    /// Matches the originating ``DiscoveredConfig/id``.
    nonisolated public let id: UUID
    /// `root`, or the governed directory name (`Tests`).
    nonisolated public let displayName: String
    /// Path relative to the workspace root (`Tests/.swiftlint.yml`).
    nonisolated public let relativePath: String
    /// Indentation level in the *config* tree (root = 0; a config whose nearest
    /// ancestor config is the root = 1), independent of directory depth.
    nonisolated public let indentLevel: Int
    /// Whether this is the workspace root config.
    nonisolated public let isRoot: Bool
    /// Short "what it changes" summary (`−2 disabled, +1 opt-in`), or nil.
    nonisolated public let badge: String?
    /// Whether this config sets `excluded`/`included` to no effect (nested).
    nonisolated public let hasIneffectiveExclusions: Bool
    /// Whether the config failed to parse.
    nonisolated public let hasParseError: Bool

    nonisolated public init(
        id: UUID,
        displayName: String,
        relativePath: String,
        indentLevel: Int,
        isRoot: Bool,
        badge: String?,
        hasIneffectiveExclusions: Bool,
        hasParseError: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.relativePath = relativePath
        self.indentLevel = indentLevel
        self.isRoot = isRoot
        self.badge = badge
        self.hasIneffectiveExclusions = hasIneffectiveExclusions
        self.hasParseError = hasParseError
    }
}

/// One rule's row in the resolved-config inspector.
public struct ResolvedRuleRow: Identifiable, Sendable {
    /// The rule identifier (also the row id).
    nonisolated public let id: String
    /// Human-readable state: `off (disabled)`, `on (opt-in)`, `warning`, `error`,
    /// `configured`, `analyzer`.
    nonisolated public let state: String
    /// The layer that set this state (`root`, `Tests`).
    nonisolated public let setBy: String
    /// Optional override detail (`overrides root`), or nil.
    nonisolated public let detail: String?

    nonisolated public var ruleIdentifier: String { id }

    nonisolated public init(id: String, state: String, setBy: String, detail: String?) {
        self.id = id
        self.state = state
        self.setBy = setBy
        self.detail = detail
    }
}

/// The resolved-config inspector content for one folder.
public struct ResolvedConfigDisplay: Sendable {
    /// The folder being inspected, relative to the workspace root (or `root`).
    nonisolated public let targetLabel: String
    /// The layer chain that applies, root → deepest (`["root", "Tests"]`).
    nonisolated public let layerChainLabels: [String]
    /// The rules the config layers changed, with attribution. (Rules left at
    /// their SwiftLint defaults are summarized by ``inheritedDefaultsNotice``
    /// rather than enumerated — that would require the full rule catalog.)
    nonisolated public let ruleRows: [ResolvedRuleRow]
    /// Set when an `only_rules` whitelist is in effect for the subtree.
    nonisolated public let onlyRulesNotice: String?
    /// Set when the root config declares `excluded`.
    nonisolated public let excludedNotice: String?
    /// Set when the folder has no config of its own (it inherits its ancestors).
    nonisolated public let inheritsNotice: String?

    nonisolated public init(
        targetLabel: String,
        layerChainLabels: [String],
        ruleRows: [ResolvedRuleRow],
        onlyRulesNotice: String?,
        excludedNotice: String?,
        inheritsNotice: String?
    ) {
        self.targetLabel = targetLabel
        self.layerChainLabels = layerChainLabels
        self.ruleRows = ruleRows
        self.onlyRulesNotice = onlyRulesNotice
        self.excludedNotice = excludedNotice
        self.inheritsNotice = inheritsNotice
    }
}

// MARK: - File marker (satisfies file_name lint rule)

private enum ConfigMapDisplay {}
