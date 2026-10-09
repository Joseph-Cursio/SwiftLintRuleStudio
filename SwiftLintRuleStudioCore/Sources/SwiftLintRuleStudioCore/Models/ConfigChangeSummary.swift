//
//  ConfigChangeSummary.swift
//  SwiftLintRuleStudio
//
//  What changed between two configurations, in terms of what SwiftLint does.
//

import Foundation
import Yams

/// How a rule's default is decided: on unless disabled, or off unless listed.
private enum RuleKind {
    case standard
    case optIn
    case analyzer
}

/// The parts of one configuration that switch rules on and off, with every rule identifier
/// under its current name.
private struct RuleSwitches {
    /// Set when `only_rules` lists anything; an empty list means default mode to SwiftLint.
    let only: Set<String>?
    let optIn: Set<String>
    let analyzer: Set<String>
    let disabled: Set<String>
    /// Rules with `enabled: false` in their settings block.
    let switchedOff: Set<String>
    let rules: [String: RuleConfiguration]
    /// `all` under `opt_in_rules` or `analyzer_rules` turns on every rule of that kind.
    let allOptIn: Bool
    let allAnalyzer: Bool

    init(_ config: YAMLConfigurationEngine.YAMLConfig) {
        // SwiftLint still reads the deprecated `enabled_rules` when `opt_in_rules` is absent.
        let optInList = config.optInRules
            ?? config.passthroughNodes["enabled_rules"]?.sequence?.compactMap(\.string)
        let optIn = Self.canonical(optInList)
        let analyzer = Self.canonical(config.analyzerRules)
        let only = Self.canonical(config.onlyRules)

        self.only = only.isEmpty ? nil : only
        self.optIn = optIn.subtracting(["all"])
        self.analyzer = analyzer.subtracting(["all"])
        allOptIn = optIn.contains("all")
        allAnalyzer = analyzer.contains("all")
        disabled = Self.canonical(config.disabledRules)
        rules = config.ruleSettings
        switchedOff = Set(rules.filter { !$0.value.enabled }.keys)
    }

    /// Every rule this configuration names.
    var named: Set<String> {
        optIn.union(analyzer).union(disabled).union(only ?? []).union(rules.keys)
    }

    /// Whether SwiftLint runs `ruleId`, by its precedence: `only_rules` (with `analyzer_rules`)
    /// decides alone; otherwise `disabled_rules` and `enabled: false` win over any list.
    func isOn(_ ruleId: String, kind: RuleKind) -> Bool {
        if let only {
            return only.contains(ruleId) || analyzer.contains(ruleId)
        }
        if disabled.contains(ruleId) || switchedOff.contains(ruleId) {
            return false
        }
        switch kind {
        case .standard:
            return true
        case .optIn:
            return allOptIn || optIn.contains(ruleId)
        case .analyzer:
            return allAnalyzer || analyzer.contains(ruleId)
        }
    }

    /// The rule's current name. Only SwiftLint's own aliases count: a rule that was "replaced
    /// by" another but still exists stays a rule of its own.
    static func canonical(_ ruleId: String) -> String {
        SwiftLintDeprecations.ruleAliases[ruleId] ?? ruleId
    }

    private static func canonical(_ ruleIds: [String]?) -> Set<String> {
        Set((ruleIds ?? []).map(canonical))
    }
}

/// What changes between two configurations, in terms of what SwiftLint does: which rules
/// start or stop running, which rule settings change, and which paths and other settings
/// change.
///
/// `ConfigDiff`'s added/removed/modified lists compare only the per-rule settings blocks,
/// so turning on an opt-in rule — an `opt_in_rules` entry — registered as no change at all.
/// This reads every list the configuration uses to switch rules on and off, by SwiftLint's
/// precedence, under each rule's current name.
///
/// Whether a rule is on by default comes from `knownRules`, the app's rule catalog. A rule
/// the catalog doesn't know is taken to be opt-in or analyzer if either configuration lists it
/// that way, and on by default otherwise — so without the catalog, taking an opt-in rule out
/// of `disabled_rules` reads as turning it on. Adding or removing `only_rules`, or `all`, also
/// changes rules neither configuration names: with the catalog those are listed too, and either
/// way the change gets a note in ``otherChanges``.
public struct ConfigChangeSummary: Equatable, Sendable {
    /// One rule whose settings change while it stays on, or stays off.
    public struct SettingChange: Equatable, Sendable, Identifiable {
        public let ruleId: String
        /// One line per changed setting, e.g. "warning: 160 → 120".
        public let details: [String]

        public var id: String { ruleId }

        public init(ruleId: String, details: [String]) {
            self.ruleId = ruleId
            self.details = details
        }
    }

    /// Rules SwiftLint runs afterwards but not before.
    public let turnedOn: [String]
    /// Rules SwiftLint runs before but not afterwards.
    public let turnedOff: [String]
    public let settingsChanged: [SettingChange]
    /// Lines such as "Now excluded: Pods".
    public let pathChanges: [String]
    /// Everything else that changes what SwiftLint does: `only_rules`, `all`, the reporter,
    /// and settings the app doesn't model, such as `custom_rules` or `warning_threshold`.
    public let otherChanges: [String]

    /// True when nothing that affects SwiftLint changes — though the text may still differ.
    public var isEmpty: Bool {
        turnedOn.isEmpty && turnedOff.isEmpty && settingsChanged.isEmpty
            && pathChanges.isEmpty && otherChanges.isEmpty
    }

    public init(
        turnedOn: [String] = [],
        turnedOff: [String] = [],
        settingsChanged: [SettingChange] = [],
        pathChanges: [String] = [],
        otherChanges: [String] = []
    ) {
        self.turnedOn = turnedOn
        self.turnedOff = turnedOff
        self.settingsChanged = settingsChanged
        self.pathChanges = pathChanges
        self.otherChanges = otherChanges
    }

    public init(
        from before: YAMLConfigurationEngine.YAMLConfig,
        to after: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule] = []
    ) {
        let old = RuleSwitches(before)
        let new = RuleSwitches(after)
        let kinds = knownRules.map { rule -> (String, RuleKind) in
            (rule.id, rule.isAnalyzer ? .analyzer : rule.isOptIn ? .optIn : .standard)
        }
        let catalog = Dictionary(kinds) { first, _ in first }
        func kind(_ ruleId: String) -> RuleKind {
            if let known = catalog[ruleId] { return known }
            if old.analyzer.contains(ruleId) || new.analyzer.contains(ruleId) { return .analyzer }
            if old.optIn.contains(ruleId) || new.optIn.contains(ruleId) { return .optIn }
            return .standard
        }

        // A rule neither configuration names can still change, through `only_rules` or `all`.
        let ruleIds = old.named.union(new.named).union(catalog.keys).sorted()
        let turnedOn = ruleIds.filter { !old.isOn($0, kind: kind($0)) && new.isOn($0, kind: kind($0)) }
        let turnedOff = ruleIds.filter { old.isOn($0, kind: kind($0)) && !new.isOn($0, kind: kind($0)) }

        // A rule switched on or off isn't also reported as reconfigured.
        let reconfigurable = Set(old.rules.keys).union(new.rules.keys)
            .subtracting(turnedOn)
            .subtracting(turnedOff)
        let settingsChanged = reconfigurable.sorted().compactMap { ruleId -> SettingChange? in
            let details = Self.settingDetails(before: old.rules[ruleId], after: new.rules[ruleId])
            return details.isEmpty ? nil : SettingChange(ruleId: ruleId, details: details)
        }

        self.init(
            turnedOn: turnedOn,
            turnedOff: turnedOff,
            settingsChanged: settingsChanged,
            pathChanges: Self.excludedChanges(before.excluded, after.excluded)
                + Self.includedChanges(before.included, after.included),
            otherChanges: Self.ruleModeChanges(old: old, new: new)
                + Self.otherSettingChanges(before: before, after: after)
        )
    }

    // MARK: - Settings

    private static func settingDetails(before: RuleConfiguration?, after: RuleConfiguration?) -> [String] {
        var details: [String] = []
        if before?.severity != after?.severity {
            let old = before?.severity?.rawValue ?? "default"
            let new = after?.severity?.rawValue ?? "default"
            details.append("severity: \(old) → \(new)")
        }
        let oldParameters = before?.parameters ?? [:]
        let newParameters = after?.parameters ?? [:]
        for key in Set(oldParameters.keys).union(newParameters.keys).sorted() {
            switch (oldParameters[key], newParameters[key]) {
            case let (old?, new?) where old != new:
                details.append("\(key): \(describe(old)) → \(describe(new))")
            case let (nil, new?):
                details.append("\(key): set to \(describe(new))")
            case let (old?, nil):
                details.append("\(key): removed (was \(describe(old)))")
            default:
                break
            }
        }
        return details
    }

    private static func describe(_ value: AnyCodable) -> String {
        value.displayText
    }

    // MARK: - Paths

    private static func excludedChanges(_ before: [String]?, _ after: [String]?) -> [String] {
        let old = before ?? []
        let new = after ?? []
        let added = new.filter { !old.contains($0) }
        let removed = old.filter { !new.contains($0) }
        return (added.isEmpty ? [] : ["Now excluded: \(added.joined(separator: ", "))"])
            + (removed.isEmpty ? [] : ["No longer excluded: \(removed.joined(separator: ", "))"])
    }

    /// `included` limits linting to its paths; without it — or with an empty list — every
    /// path is linted. So adding or removing the list changes far more than the paths it names.
    private static func includedChanges(_ before: [String]?, _ after: [String]?) -> [String] {
        let old = before ?? []
        let new = after ?? []
        switch (old.isEmpty, new.isEmpty) {
        case (true, true):
            return []
        case (true, false):
            return ["Only these paths are linted now: \(new.joined(separator: ", "))"]
        case (false, true):
            return ["included removed: every path is linted again"]
        case (false, false):
            let added = new.filter { !old.contains($0) }
            let removed = old.filter { !new.contains($0) }
            return (added.isEmpty ? [] : ["Now included: \(added.joined(separator: ", "))"])
                + (removed.isEmpty ? [] : ["No longer included: \(removed.joined(separator: ", "))"])
        }
    }

    // MARK: - Other settings

    private static func ruleModeChanges(old: RuleSwitches, new: RuleSwitches) -> [String] {
        var lines: [String] = []
        switch (old.only, new.only) {
        case let (nil, only?):
            let count = only.count
            lines.append("only_rules added: only the \(count) rule\(count == 1 ? "" : "s") it lists run now")
        case (_?, nil):
            lines.append("only_rules removed: SwiftLint's default rules run again, plus any opt-in rules listed")
        default:
            break
        }
        if old.allOptIn != new.allOptIn {
            lines.append(new.allOptIn
                ? "opt_in_rules: all — every opt-in rule runs now"
                : "opt_in_rules no longer lists all: only the opt-in rules it names run")
        }
        if old.allAnalyzer != new.allAnalyzer {
            lines.append(new.allAnalyzer
                ? "analyzer_rules: all — every analyzer rule runs now"
                : "analyzer_rules no longer lists all: only the analyzer rules it names run")
        }
        return lines
    }

    private static func otherSettingChanges(
        before: YAMLConfigurationEngine.YAMLConfig,
        after: YAMLConfigurationEngine.YAMLConfig
    ) -> [String] {
        var lines: [String] = []
        if before.reporter != after.reporter {
            lines.append("reporter: \(before.reporter ?? "default") → \(after.reporter ?? "default")")
        }
        // `enabled_rules` is read as `opt_in_rules` above, and a rule's `[warning, error]` list
        // as its settings, so their changes are already counted.
        let keys = Set(before.passthroughNodes.keys).union(after.passthroughNodes.keys)
            .subtracting(["enabled_rules"])
            .subtracting(before.levelListRules.keys)
            .subtracting(after.levelListRules.keys)
        for key in keys.sorted() {
            switch (before.passthroughNodes[key], after.passthroughNodes[key]) {
            case let (old?, new?) where !sameValue(old, new):
                if let oldScalar = old.scalar?.string, let newScalar = new.scalar?.string {
                    lines.append("\(key): \(oldScalar) → \(newScalar)")
                } else {
                    lines.append("\(key) changed")
                }
            case (nil, _?):
                lines.append("\(key) added")
            case (_?, nil):
                lines.append("\(key) removed")
            default:
                break
            }
        }
        return lines
    }

    /// Whether two settings the engine doesn't model hold the same value, whatever order their
    /// keys are written in. Comparing the nodes themselves counts key order.
    private static func sameValue(_ lhs: Node, _ rhs: Node) -> Bool {
        guard let left = try? YAMLConfigurationEngine.nodeToAny(lhs),
              let right = try? YAMLConfigurationEngine.nodeToAny(rhs) else { return lhs == rhs }
        return LayoutPreservingEdit.sameValue(left, right)
    }
}

extension YAMLConfigurationEngine.YAMLConfig {
    /// Every rule this configuration names, under its current name.
    var namedRuleIds: Set<String> {
        RuleSwitches(self).named
    }

    /// Each rule's settings block under the rule's current name, including the list form of
    /// its warning and error levels. A config with blocks under both an old name and the
    /// current one is rejected by SwiftLint; here the current name's block wins.
    var ruleSettings: [String: RuleConfiguration] {
        var settings: [String: RuleConfiguration] = [:]
        for (key, configuration) in rules.merging(levelListRules, uniquingKeysWith: { block, _ in block }) {
            let ruleId = RuleSwitches.canonical(key)
            if settings[ruleId] == nil || key == ruleId {
                settings[ruleId] = configuration
            }
        }
        return settings
    }

    /// Rules set with SwiftLint's list form of their levels — `type_body_length: [300, 400]`
    /// for a warning at 300 and an error at 400 — which the engine keeps as an unmodelled key.
    /// Keyed as written.
    var levelListRules: [String: RuleConfiguration] {
        var settings: [String: RuleConfiguration] = [:]
        for (key, node) in passthroughNodes {
            guard let items = node.sequence, (1...2).contains(items.count) else { continue }
            let levels = items.compactMap(\.int)
            guard levels.count == items.count else { continue }
            let parameters = zip(["warning", "error"], levels).map { ($0, AnyCodable($1)) }
            settings[key] = RuleConfiguration(
                enabled: true,
                parameters: Dictionary(uniqueKeysWithValues: parameters)
            )
        }
        return settings
    }
}

public extension YAMLConfigurationEngine.ConfigDiff {
    /// This diff with its change summary worked out again using the rule catalog, which says
    /// for certain which rules are opt-in. Unchanged when the diff carries no summary, the
    /// catalog is empty, or either side doesn't parse.
    func knowing(_ rules: [Rule]) -> Self {
        guard changes != nil, !rules.isEmpty,
              let old = try? YAMLConfigurationEngine.parse(before),
              let new = try? YAMLConfigurationEngine.parse(after) else { return self }
        return Self(
            addedRules: addedRules,
            removedRules: removedRules,
            modifiedRules: modifiedRules,
            before: before,
            after: after,
            changes: ConfigChangeSummary(from: old, to: new, knownRules: rules)
        )
    }
}
