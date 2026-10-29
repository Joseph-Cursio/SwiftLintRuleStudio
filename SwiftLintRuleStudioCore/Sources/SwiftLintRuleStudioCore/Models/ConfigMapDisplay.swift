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
    /// Matches the originating ``DiscoveredConfig/id`` — the config file's path.
    nonisolated public let id: URL
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
    /// The nested config this one takes the place of beneath its folder — its
    /// parent row, when that is neither the root nor a config the root pulls in
    /// with `parent_config`/`child_config` (`Sub` for `Sub/Deeper`). SwiftLint
    /// merges a file's nearest nested config onto the root config alone, so files
    /// under this config's folder get none of that config's settings.
    nonisolated public let replaces: String?
    /// The configs the root config pulls in that have no row of their own — files
    /// outside the workspace or under another name, remote configs — by their
    /// display names, in the order SwiftLint merges them. Empty on every row but
    /// the root's.
    nonisolated public let pullsIn: [String]

    nonisolated public init(
        id: URL,
        displayName: String,
        relativePath: String,
        indentLevel: Int,
        isRoot: Bool,
        badge: String?,
        hasIneffectiveExclusions: Bool,
        hasParseError: Bool,
        replaces: String?,
        pullsIn: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.relativePath = relativePath
        self.indentLevel = indentLevel
        self.isRoot = isRoot
        self.badge = badge
        self.hasIneffectiveExclusions = hasIneffectiveExclusions
        self.hasParseError = hasParseError
        self.replaces = replaces
        self.pullsIn = pullsIn
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
    /// Set when the root configuration excludes anything.
    nonisolated public let excludedNotice: String?
    /// Set when the folder has no config of its own (it inherits its ancestors).
    nonisolated public let inheritsNotice: String?
    /// Set when nested configs in folders above this one don't apply here:
    /// SwiftLint applies the root config and the nearest nested config alone.
    nonisolated public let skippedNotice: String?
    /// Set when a config the root pulls in from beyond the workspace's own files
    /// couldn't be read — a remote config SwiftLint hasn't fetched yet, or a file
    /// that doesn't parse — so the settings shown leave out its own.
    nonisolated public let unreadNotice: String?

    nonisolated public init(
        targetLabel: String,
        layerChainLabels: [String],
        ruleRows: [ResolvedRuleRow],
        onlyRulesNotice: String?,
        excludedNotice: String?,
        inheritsNotice: String?,
        skippedNotice: String?,
        unreadNotice: String?
    ) {
        self.targetLabel = targetLabel
        self.layerChainLabels = layerChainLabels
        self.ruleRows = ruleRows
        self.onlyRulesNotice = onlyRulesNotice
        self.excludedNotice = excludedNotice
        self.inheritsNotice = inheritsNotice
        self.skippedNotice = skippedNotice
        self.unreadNotice = unreadNotice
    }
}

// MARK: - File marker (satisfies file_name lint rule)

private enum ConfigMapDisplay {}
