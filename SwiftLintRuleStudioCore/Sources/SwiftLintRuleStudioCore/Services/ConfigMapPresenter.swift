//
//  ConfigMapPresenter.swift
//  SwiftLintRuleStudio
//
//  Turns a ConfigTree / ResolvedConfiguration into display models for the Config
//  Map UI. Keeping this here (rather than in the app's view model) keeps the
//  presentation logic unit-testable in the Core package.
//

import Foundation

/// Builds Config Map display models from the discovery and resolution engines.
public struct ConfigMapPresenter {
    /// Creates a presenter.
    nonisolated public init() {}

    // MARK: - Sparse config tree

    /// Builds the sparse Config Tree rows in pre-order (root, then each child
    /// subtree), indented by position in the *config* tree rather than directory
    /// depth — so a deep config whose nearest ancestor config is the root still
    /// sits one level under it.
    ///
    /// Nesting follows folders, not merging: SwiftLint merges each nested config
    /// onto the root alone. So a row under a nested config's row says which config
    /// it replaces, lest it read as building on it — unless the root pulls that
    /// config in, which makes it part of the root's settings everywhere.
    public func treeRows(for tree: ConfigTree) -> [ConfigTreeRow] {
        var childrenByParent: [URL: [DiscoveredConfig]] = [:]
        var roots: [DiscoveredConfig] = []
        for config in tree.configs {
            if let parentID = config.parentID {
                childrenByParent[parentID, default: []].append(config)
            } else {
                roots.append(config)
            }
        }

        var rows: [ConfigTreeRow] = []
        func visit(_ config: DiscoveredConfig, parent: DiscoveredConfig?, level: Int) {
            let replaced = parent.flatMap { $0.isRoot || $0.rootGraphPosition != nil ? nil : $0 }
            rows.append(Self.row(for: config, indentLevel: level, replacing: replaced))
            let children = (childrenByParent[config.id] ?? [])
                .sorted { $0.relativePath < $1.relativePath }
            for child in children {
                visit(child, parent: config, level: level + 1)
            }
        }
        for root in roots.sorted(by: { $0.relativePath < $1.relativePath }) {
            visit(root, parent: nil, level: 0)
        }
        return rows
    }

    // MARK: - Resolved-config inspector

    /// Builds the resolved-config inspector content for a folder.
    public func display(for resolved: ResolvedConfiguration, in tree: ConfigTree) -> ResolvedConfigDisplay {
        ResolvedConfigDisplay(
            targetLabel: Self.relativeLabel(of: resolved.targetDirectory, root: tree.workspaceRoot),
            layerChainLabels: resolved.layerChain.map(\.displayName),
            ruleRows: Self.ruleRows(for: resolved),
            onlyRulesNotice: Self.onlyRulesNotice(for: resolved),
            excludedNotice: Self.excludedNotice(for: resolved),
            inheritsNotice: Self.inheritsNotice(for: resolved, in: tree),
            skippedNotice: Self.skippedNotice(for: resolved)
        )
    }

    // MARK: - Tree row helpers

    private static func row(
        for config: DiscoveredConfig,
        indentLevel: Int,
        replacing replaced: DiscoveredConfig?
    ) -> ConfigTreeRow {
        ConfigTreeRow(
            id: config.id,
            displayName: config.displayName,
            relativePath: config.relativePath,
            indentLevel: indentLevel,
            isRoot: config.isRoot,
            badge: badge(for: config),
            hasIneffectiveExclusions: config.hasIneffectiveExclusions,
            hasParseError: config.parseError != nil,
            replaces: replaced?.directoryPath.lastPathComponent
        )
    }

    /// A short "what this config changes" badge.
    static func badge(for config: DiscoveredConfig) -> String? {
        if config.parseError != nil { return "parse error" }
        let summary = config.summary
        if summary.declaresOnlyRules {
            // Rules, not entries, as SwiftLint reads the list and the inspector's notice
            // counts it: an alias beside its rule's current name is one rule.
            let count = Set((summary.onlyRules ?? []).map(SwiftLintDeprecations.currentName(of:))).count
            return "only \(count) rule\(count == 1 ? "" : "s")"
        }
        var parts: [String] = []
        if summary.disabledRuleCount > 0 { parts.append("-\(summary.disabledRuleCount) disabled") }
        if summary.optInRuleCount > 0 { parts.append("+\(summary.optInRuleCount) opt-in") }
        if summary.configuredRuleCount > 0 { parts.append("\(summary.configuredRuleCount) configured") }
        if summary.analyzerRuleCount > 0 { parts.append("\(summary.analyzerRuleCount) analyzer") }
        if parts.isEmpty {
            return summary.declaresNoChanges ? "no rule changes" : "config only"
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Resolved display helpers

    private static func ruleRows(for resolved: ResolvedConfiguration) -> [ResolvedRuleRow] {
        var rowsByRule: [String: ResolvedRuleRow] = [:]
        for decision in resolved.disabledRules {
            rowsByRule[decision.identifier] = ResolvedRuleRow(
                id: decision.identifier, state: "off (disabled)", setBy: decision.setBy.displayName, detail: nil
            )
        }
        for decision in resolved.optInRules where rowsByRule[decision.identifier] == nil {
            rowsByRule[decision.identifier] = ResolvedRuleRow(
                id: decision.identifier, state: "on (opt-in)", setBy: decision.setBy.displayName, detail: nil
            )
        }
        for decision in resolved.analyzerRules where rowsByRule[decision.identifier] == nil {
            rowsByRule[decision.identifier] = ResolvedRuleRow(
                id: decision.identifier, state: "analyzer", setBy: decision.setBy.displayName, detail: nil
            )
        }
        for configuration in resolved.ruleConfigurations where rowsByRule[configuration.identifier] == nil {
            let runs = resolved.onlyRules?.contains(configuration.identifier) ?? true
            rowsByRule[configuration.identifier] = ResolvedRuleRow(
                id: configuration.identifier,
                state: runs ? state(for: configuration.configuration) : "off (not in only_rules)",
                setBy: configuration.setBy.displayName,
                detail: configuration.overridesAncestor
                    ? "overrides \(configuration.previousSetBy?.displayName ?? "ancestor")"
                    : nil
            )
        }
        // In only_rules mode the whitelist is what runs, so each of its rules gets a row.
        for decision in resolved.onlyRules?.rules ?? [] where rowsByRule[decision.identifier] == nil {
            rowsByRule[decision.identifier] = ResolvedRuleRow(
                id: decision.identifier, state: "on (only_rules)", setBy: decision.setBy.displayName, detail: nil
            )
        }
        return rowsByRule.values.sorted { $0.id < $1.id }
    }

    private static func state(for configuration: RuleConfiguration) -> String {
        if let severity = configuration.severity { return severity.rawValue }
        if configuration.enabled == false { return "off (disabled)" }
        if configuration.parameters?.isEmpty == false { return "configured" }
        return "enabled"
    }

    private static func onlyRulesNotice(for resolved: ResolvedConfiguration) -> String? {
        guard let onlyRules = resolved.onlyRules else { return nil }
        let count = onlyRules.rules.count
        let declaredBy = onlyRules.declaredBy.displayName
        return "Only \(count) rule\(count == 1 ? "" : "s") run here — only_rules set by \(declaredBy)."
    }

    /// What the root configuration excludes, each entry with the config that
    /// excludes it: `excluded (root): Generated`, or, from several configs,
    /// `excluded: ../../Pods (../../.swiftlint.yml); Generated (root)`.
    private static func excludedNotice(for resolved: ResolvedConfiguration) -> String? {
        var groups: [(layer: ConfigLayer, paths: [String])] = []
        for entry in resolved.excluded {
            if let last = groups.last, last.layer.id == entry.setBy.id {
                groups[groups.count - 1].paths.append(entry.value)
            } else {
                groups.append((entry.setBy, [entry.value]))
            }
        }
        guard let first = groups.first else { return nil }
        guard groups.count > 1 else {
            return "excluded (\(first.layer.displayName)): \(first.paths.joined(separator: ", "))"
        }
        let named = groups.map { "\($0.paths.joined(separator: ", ")) (\($0.layer.displayName))" }
        return "excluded: \(named.joined(separator: "; "))"
    }

    private static func inheritsNotice(for resolved: ResolvedConfiguration, in tree: ConfigTree) -> String? {
        let targetPath = resolved.targetDirectory.standardizedFileURL.path
        let definesOwnConfig = tree.configs.contains {
            $0.directoryPath.standardizedFileURL.path == targetPath
        }
        guard definesOwnConfig == false else { return nil }
        // The configs the root pulls in are part of the root's settings, not a
        // layer the folder inherits from in their own right.
        let rootGraph = Set(tree.rootGraph.filter { !$0.isRoot }.map(\.id))
        let inheritedFrom = resolved.layerChain.last { !rootGraph.contains($0.id) }?.displayName
            ?? "the SwiftLint defaults"
        return "No config in this folder — it inherits from \(inheritedFrom)."
    }

    /// Names the nested configs above the folder that don't apply here. Without it
    /// the chain `root ▸ Deeper` reads as though `Sub`, between them, had been
    /// forgotten rather than passed over.
    private static func skippedNotice(for resolved: ResolvedConfiguration) -> String? {
        guard let nearest = resolved.layerChain.last(where: { !$0.isRoot }),
              let last = resolved.skippedLayers.last else { return nil }
        let names = resolved.skippedLayers.map(\.displayName)
        let skipped = names.count == 1
            ? "\(last.displayName)'s config doesn't"
            : "The configs in \(names.dropLast().joined(separator: ", ")) and \(last.displayName) don't"
        let applied = resolved.layerChain.contains(where: \.isRoot) ? "the root config and " : ""
        return "\(skipped) apply here — SwiftLint applies only \(applied)the nearest nested config, "
            + "\(nearest.displayName)."
    }

    private static func relativeLabel(of directory: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents
        guard directoryComponents.count > rootComponents.count else { return "root" }
        return directoryComponents.suffix(from: rootComponents.count).joined(separator: "/")
    }
}
