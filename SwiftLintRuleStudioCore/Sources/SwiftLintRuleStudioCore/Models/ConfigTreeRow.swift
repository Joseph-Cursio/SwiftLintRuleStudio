//
//  ConfigTreeRow.swift
//  SwiftLintRuleStudio
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
