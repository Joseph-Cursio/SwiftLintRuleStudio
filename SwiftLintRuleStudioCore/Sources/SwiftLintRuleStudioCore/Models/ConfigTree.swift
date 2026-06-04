//
//  ConfigTree.swift
//  SwiftLintRuleStudio
//
//  Data model for the workspace's nested `.swiftlint.yml` configuration tree.
//  SwiftLint merges a `.swiftlint.yml` in a subdirectory with its ancestors and
//  applies it to files beneath that directory. The GUI historically saw only the
//  root config; these types make the whole tree first-class so it can be shown,
//  inspected, and edited. See docs/nested-config-visibility.md.
//

import Foundation

/// The parsed representation of a `.swiftlint.yml`, as produced by
/// ``YAMLConfigurationEngine``. Aliased here so the config-tree types can refer
/// to it without the nested-type spelling.
public typealias YAMLConfig = YAMLConfigurationEngine.YAMLConfig

/// A summary of what a single `.swiftlint.yml` *declares on its own* — not the
/// resolved/merged view (that is the resolved-config inspector's job). Drives
/// the per-node "what it changes" badge in the Config Tree.
public struct ConfigSummary: Sendable {
    /// Count of entries under `disabled_rules`.
    nonisolated public let disabledRuleCount: Int
    /// Count of entries under `opt_in_rules`.
    nonisolated public let optInRuleCount: Int
    /// Count of entries under `analyzer_rules`.
    nonisolated public let analyzerRuleCount: Int
    /// Count of rules given an explicit configuration (severity/params).
    nonisolated public let configuredRuleCount: Int
    /// `only_rules` whitelist, if present. When set, this layer hard-resets the
    /// active rule set for its subtree.
    nonisolated public let onlyRules: [String]?
    /// Whether the config sets `excluded:`.
    nonisolated public let setsExcluded: Bool
    /// Whether the config sets `included:`.
    nonisolated public let setsIncluded: Bool
    /// Whether the config sets `reporter:`.
    nonisolated public let setsReporter: Bool

    nonisolated public init(
        disabledRuleCount: Int,
        optInRuleCount: Int,
        analyzerRuleCount: Int,
        configuredRuleCount: Int,
        onlyRules: [String]?,
        setsExcluded: Bool,
        setsIncluded: Bool,
        setsReporter: Bool
    ) {
        self.disabledRuleCount = disabledRuleCount
        self.optInRuleCount = optInRuleCount
        self.analyzerRuleCount = analyzerRuleCount
        self.configuredRuleCount = configuredRuleCount
        self.onlyRules = onlyRules
        self.setsExcluded = setsExcluded
        self.setsIncluded = setsIncluded
        self.setsReporter = setsReporter
    }

    /// An empty summary — used when a config could not be parsed.
    nonisolated public static let empty = Self(
        disabledRuleCount: 0,
        optInRuleCount: 0,
        analyzerRuleCount: 0,
        configuredRuleCount: 0,
        onlyRules: nil,
        setsExcluded: false,
        setsIncluded: false,
        setsReporter: false
    )

    /// Whether the config declares an `only_rules` whitelist.
    nonisolated public var declaresOnlyRules: Bool { onlyRules != nil }

    /// Total number of rule-affecting declarations (disabled + opt-in + analyzer
    /// + explicitly-configured).
    nonisolated public var declaredRuleChangeCount: Int {
        disabledRuleCount + optInRuleCount + analyzerRuleCount + configuredRuleCount
    }

    /// A config file that exists but changes nothing — often an accidental
    /// leftover ("Config present, no rule changes" in the doc's design).
    nonisolated public var declaresNoChanges: Bool {
        declaredRuleChangeCount == 0 && onlyRules == nil
            && !setsExcluded && !setsIncluded && !setsReporter
    }
}

/// A single `.swiftlint.yml` discovered in the workspace, with its parsed
/// contents and where it sits in the directory hierarchy.
public struct DiscoveredConfig: Identifiable, Sendable {
    nonisolated public let id: UUID
    /// Absolute path to the `.swiftlint.yml` file.
    nonisolated public let configPath: URL
    /// The directory this config governs (the file's parent directory).
    nonisolated public let directoryPath: URL
    /// Path of the config file relative to the workspace root, e.g.
    /// `Tests/.swiftlint.yml`. The root config is `.swiftlint.yml`.
    nonisolated public let relativePath: String
    /// Directory depth below the workspace root. The root config is `0`.
    nonisolated public let depth: Int
    /// Whether this config sits at the workspace root.
    nonisolated public let isRoot: Bool
    /// The id of the nearest ancestor config (its parent layer), or `nil` for the
    /// top-most discovered config.
    nonisolated public let parentID: UUID?
    /// The parsed configuration, or `nil` if it failed to parse.
    nonisolated public let config: YAMLConfig?
    /// A human-readable parse error, when `config` is `nil`.
    nonisolated public let parseError: String?
    /// What this config declares on its own.
    nonisolated public let summary: ConfigSummary

    nonisolated public init(
        id: UUID,
        configPath: URL,
        directoryPath: URL,
        relativePath: String,
        depth: Int,
        isRoot: Bool,
        parentID: UUID?,
        config: YAMLConfig?,
        parseError: String?,
        summary: ConfigSummary
    ) {
        self.id = id
        self.configPath = configPath
        self.directoryPath = directoryPath
        self.relativePath = relativePath
        self.depth = depth
        self.isRoot = isRoot
        self.parentID = parentID
        self.config = config
        self.parseError = parseError
        self.summary = summary
    }

    /// A nested config that sets `excluded:`/`included:` — which SwiftLint
    /// **ignores** outside the root config. This is the "excluded trap" from the
    /// doc: the developer thinks they excluded a file, but it is still linted.
    nonisolated public var hasIneffectiveExclusions: Bool {
        !isRoot && (summary.setsExcluded || summary.setsIncluded)
    }
}

/// The full set of `.swiftlint.yml` configs discovered in a workspace, linked
/// into a parent/child hierarchy by directory nesting.
public struct ConfigTree: Sendable {
    /// The workspace root the tree was discovered from.
    nonisolated public let workspaceRoot: URL
    /// Every discovered config, sorted by path (root first).
    nonisolated public let configs: [DiscoveredConfig]

    nonisolated public init(workspaceRoot: URL, configs: [DiscoveredConfig]) {
        self.workspaceRoot = workspaceRoot
        self.configs = configs
    }

    /// The config at the workspace root, if one exists.
    nonisolated public var rootConfig: DiscoveredConfig? {
        configs.first(where: \.isRoot)
    }

    /// All configs below the workspace root.
    nonisolated public var nestedConfigs: [DiscoveredConfig] {
        configs.filter { !$0.isRoot }
    }

    /// Whether the workspace has no `.swiftlint.yml` at all.
    nonisolated public var isEmpty: Bool { configs.isEmpty }

    /// The immediate children of a config (configs whose parent is `parent`).
    nonisolated public func children(of parent: DiscoveredConfig) -> [DiscoveredConfig] {
        configs.filter { $0.parentID == parent.id }
    }

    /// Nested configs that set `excluded`/`included` to no effect — the cases
    /// worth flagging to the developer (see ``DiscoveredConfig/hasIneffectiveExclusions``).
    nonisolated public var configsWithIneffectiveExclusions: [DiscoveredConfig] {
        configs.filter(\.hasIneffectiveExclusions)
    }
}
