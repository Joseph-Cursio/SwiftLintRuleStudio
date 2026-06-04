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
    public func treeRows(for tree: ConfigTree) -> [ConfigTreeRow] {
        var childrenByParent: [UUID: [DiscoveredConfig]] = [:]
        var roots: [DiscoveredConfig] = []
        for config in tree.configs {
            if let parentID = config.parentID {
                childrenByParent[parentID, default: []].append(config)
            } else {
                roots.append(config)
            }
        }

        var rows: [ConfigTreeRow] = []
        func visit(_ config: DiscoveredConfig, level: Int) {
            rows.append(Self.row(for: config, indentLevel: level))
            let children = (childrenByParent[config.id] ?? [])
                .sorted { $0.relativePath < $1.relativePath }
            for child in children {
                visit(child, level: level + 1)
            }
        }
        for root in roots.sorted(by: { $0.relativePath < $1.relativePath }) {
            visit(root, level: 0)
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
            inheritsNotice: Self.inheritsNotice(for: resolved, in: tree)
        )
    }

    // MARK: - Tree row helpers

    private static func row(for config: DiscoveredConfig, indentLevel: Int) -> ConfigTreeRow {
        ConfigTreeRow(
            id: config.id,
            displayName: config.isRoot ? "root" : config.directoryPath.lastPathComponent,
            relativePath: config.relativePath,
            indentLevel: indentLevel,
            isRoot: config.isRoot,
            badge: badge(for: config),
            hasIneffectiveExclusions: config.hasIneffectiveExclusions,
            hasParseError: config.parseError != nil
        )
    }

    /// A short "what this config changes" badge.
    static func badge(for config: DiscoveredConfig) -> String? {
        if config.parseError != nil { return "parse error" }
        let summary = config.summary
        if summary.declaresOnlyRules {
            let count = summary.onlyRules?.count ?? 0
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
            rowsByRule[configuration.identifier] = ResolvedRuleRow(
                id: configuration.identifier,
                state: state(for: configuration.configuration),
                setBy: configuration.setBy.displayName,
                detail: configuration.overridesAncestor
                    ? "overrides \(configuration.previousSetBy?.displayName ?? "ancestor")"
                    : nil
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
        let count = onlyRules.value.count
        return "Only \(count) rule\(count == 1 ? "" : "s") run here — only_rules set by \(onlyRules.setBy.displayName)."
    }

    private static func excludedNotice(for resolved: ResolvedConfiguration) -> String? {
        guard let excluded = resolved.excluded else { return nil }
        return "excluded (\(excluded.setBy.displayName)): \(excluded.value.joined(separator: ", "))"
    }

    private static func inheritsNotice(for resolved: ResolvedConfiguration, in tree: ConfigTree) -> String? {
        let targetPath = resolved.targetDirectory.standardizedFileURL.path
        let definesOwnConfig = tree.configs.contains {
            $0.directoryPath.standardizedFileURL.path == targetPath
        }
        guard definesOwnConfig == false else { return nil }
        let inheritedFrom = resolved.layerChain.last?.displayName ?? "the SwiftLint defaults"
        return "No config in this folder — it inherits from \(inheritedFrom)."
    }

    private static func relativeLabel(of directory: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents
        guard directoryComponents.count > rootComponents.count else { return "root" }
        return directoryComponents.suffix(from: rootComponents.count).joined(separator: "/")
    }
}
