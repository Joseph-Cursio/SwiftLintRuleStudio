//
//  ConfigComparisonService.swift
//  SwiftLintRuleStudio
//
//  Side-by-side comparison of SwiftLint configurations from two workspaces
//

import Foundation

/// Represents the difference for a single rule between two configs
public struct RuleComparisonDiff: Identifiable, Sendable {
    public let id: String
    public let ruleId: String
    public let firstConfig: RuleConfiguration?
    public let secondConfig: RuleConfiguration?
    public let differences: [String]

    public init(
        id: String,
        ruleId: String,
        firstConfig: RuleConfiguration?,
        secondConfig: RuleConfiguration?,
        differences: [String]
    ) {
        self.id = id
        self.ruleId = ruleId
        self.firstConfig = firstConfig
        self.secondConfig = secondConfig
        self.differences = differences
    }
}

/// Result of comparing two configurations, in terms of what SwiftLint does with each.
public struct ConfigComparisonResult: Sendable {
    /// Rules SwiftLint runs with the first config but not the second.
    public let onlyInFirst: [String]
    /// Rules SwiftLint runs with the second config but not the first.
    public let onlyInSecond: [String]
    /// Rules on, or off, under both, with settings that differ.
    public let inBothDifferent: [RuleComparisonDiff]
    /// Rules either config names that SwiftLint treats the same way under both.
    public let inBothSame: [String]
    /// Lines such as "Excluded only in Server: Tests".
    public let pathDifferences: [String]
    /// Other settings that differ, read first → second: `only_rules`, the reporter, `custom_rules`.
    public let otherDifferences: [String]
    public let diff: YAMLConfigurationEngine.ConfigDiff

    public init(
        onlyInFirst: [String],
        onlyInSecond: [String],
        inBothDifferent: [RuleComparisonDiff],
        inBothSame: [String],
        diff: YAMLConfigurationEngine.ConfigDiff,
        pathDifferences: [String] = [],
        otherDifferences: [String] = []
    ) {
        self.onlyInFirst = onlyInFirst
        self.onlyInSecond = onlyInSecond
        self.inBothDifferent = inBothDifferent
        self.inBothSame = inBothSame
        self.pathDifferences = pathDifferences
        self.otherDifferences = otherDifferences
        self.diff = diff
    }

    public var totalDifferences: Int {
        onlyInFirst.count + onlyInSecond.count + inBothDifferent.count
            + pathDifferences.count + otherDifferences.count
    }
}

/// Protocol for config comparison service
public protocol ConfigComparisonServiceProtocol: Sendable {
    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String
    ) throws -> ConfigComparisonResult

    /// The comparison, with the rule catalog saying for certain which rules are opt-in.
    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String,
        knownRules: [Rule]
    ) throws -> ConfigComparisonResult
}

/// Compares the SwiftLint configurations of two projects by what SwiftLint does with each: which
/// rules run under one and not the other, which run under both but are set differently, and which
/// paths and other settings differ. It reads every list a config uses to switch rules on and off —
/// `opt_in_rules`, `disabled_rules`, `analyzer_rules`, `only_rules` — not just per-rule settings.
public final class ConfigComparisonService: ConfigComparisonServiceProtocol {

    public init() {}

    public func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String
    ) throws -> ConfigComparisonResult {
        try compare(config1: config1, label1: label1, config2: config2, label2: label2, knownRules: [])
    }

    public func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String,
        knownRules: [Rule]
    ) throws -> ConfigComparisonResult {
        let cfg1 = try YAMLConfigurationEngine.loadConfig(at: config1)
        let cfg2 = try YAMLConfigurationEngine.loadConfig(at: config2)
        let summary = ConfigChangeSummary(from: cfg1, to: cfg2, knownRules: knownRules)

        let settings1 = cfg1.ruleSettings
        let settings2 = cfg2.ruleSettings
        let inBothDifferent = summary.settingsChanged.map { change in
            buildRuleDiff(
                ruleId: change.ruleId,
                rc1: settings1[change.ruleId],
                rc2: settings2[change.ruleId],
                label1: label1,
                label2: label2
            )
        }
        let differing = Set(summary.turnedOn + summary.turnedOff + summary.settingsChanged.map(\.ruleId))
        let named = cfg1.namedRuleIds.union(cfg2.namedRuleIds)

        let content1 = (try? String(contentsOf: config1, encoding: .utf8)) ?? ""
        let content2 = (try? String(contentsOf: config2, encoding: .utf8)) ?? ""

        return ConfigComparisonResult(
            onlyInFirst: summary.turnedOff,
            onlyInSecond: summary.turnedOn,
            inBothDifferent: inBothDifferent,
            inBothSame: named.subtracting(differing).sorted(),
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: summary.turnedOn,
                removedRules: summary.turnedOff,
                modifiedRules: inBothDifferent.map(\.ruleId),
                before: content1,
                after: content2
            ),
            pathDifferences: Self.listDifferences(cfg1.excluded, cfg2.excluded, noun: "Excluded", label1, label2)
                + Self.includedDifferences(cfg1.included, cfg2.included, label1, label2),
            otherDifferences: summary.otherChanges
        )
    }

    /// One line per setting that differs, naming the config that has each value.
    func buildRuleDiff(
        ruleId: String,
        rc1: RuleConfiguration?,
        rc2: RuleConfiguration?,
        label1: String,
        label2: String
    ) -> RuleComparisonDiff {
        var differences: [String] = []
        if rc1?.severity != rc2?.severity {
            let sev1 = rc1?.severity?.rawValue ?? "default"
            let sev2 = rc2?.severity?.rawValue ?? "default"
            differences.append("severity: \(label1) \(sev1), \(label2) \(sev2)")
        }
        let parameters1 = rc1?.parameters ?? [:]
        let parameters2 = rc2?.parameters ?? [:]
        for key in Set(parameters1.keys).union(parameters2.keys).sorted() {
            switch (parameters1[key], parameters2[key]) {
            case let (value1?, value2?) where value1 != value2:
                differences.append("\(key): \(label1) \(value1.displayText), \(label2) \(value2.displayText)")
            case let (value1?, nil):
                differences.append("\(key): only \(label1) sets it (\(value1.displayText))")
            case let (nil, value2?):
                differences.append("\(key): only \(label2) sets it (\(value2.displayText))")
            default:
                break
            }
        }
        return RuleComparisonDiff(
            id: ruleId, ruleId: ruleId,
            firstConfig: rc1, secondConfig: rc2,
            differences: differences
        )
    }

    // MARK: - Helpers

    private static func listDifferences(
        _ list1: [String]?,
        _ list2: [String]?,
        noun: String,
        _ label1: String,
        _ label2: String
    ) -> [String] {
        let first = list1 ?? []
        let second = list2 ?? []
        let onlyFirst = first.filter { !second.contains($0) }
        let onlySecond = second.filter { !first.contains($0) }
        return (onlyFirst.isEmpty ? [] : ["\(noun) only in \(label1): \(onlyFirst.joined(separator: ", "))"])
            + (onlySecond.isEmpty ? [] : ["\(noun) only in \(label2): \(onlySecond.joined(separator: ", "))"])
    }

    /// `included` limits linting to its paths; without it every path is linted, so a config
    /// with the list and one without differ in far more than the paths it names.
    private static func includedDifferences(
        _ list1: [String]?,
        _ list2: [String]?,
        _ label1: String,
        _ label2: String
    ) -> [String] {
        let first = list1 ?? []
        let second = list2 ?? []
        switch (first.isEmpty, second.isEmpty) {
        case (true, true):
            return []
        case (false, true):
            return ["\(label1) lints only \(first.joined(separator: ", ")); \(label2) lints every path"]
        case (true, false):
            return ["\(label2) lints only \(second.joined(separator: ", ")); \(label1) lints every path"]
        case (false, false):
            return listDifferences(first, second, noun: "Included", label1, label2)
        }
    }
}

public extension ConfigComparisonServiceProtocol {
    /// Without the catalog, which rules are opt-in is inferred from the configs themselves.
    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String,
        knownRules _: [Rule]
    ) throws -> ConfigComparisonResult {
        try compare(config1: config1, label1: label1, config2: config2, label2: label2)
    }
}
