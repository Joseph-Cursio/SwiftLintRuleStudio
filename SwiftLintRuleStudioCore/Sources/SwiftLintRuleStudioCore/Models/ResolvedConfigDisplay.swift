//
//  ResolvedConfigDisplay.swift
//  SwiftLintRuleStudio
//

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
