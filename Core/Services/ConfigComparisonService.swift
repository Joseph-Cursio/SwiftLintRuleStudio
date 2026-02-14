//
//  ConfigComparisonService.swift
//  SwiftLintRuleStudio
//
//  Side-by-side comparison of SwiftLint configurations from two workspaces
//

import Foundation

/// Represents the difference for a single rule between two configs
struct RuleComparisonDiff: Identifiable, Sendable {
    let id: String // ruleId
    let ruleId: String
    let firstConfig: RuleConfiguration?
    let secondConfig: RuleConfiguration?
    let differences: [String]
}

/// Result of comparing two configurations
struct ConfigComparisonResult: Sendable {
    let onlyInFirst: [String]
    let onlyInSecond: [String]
    let inBothDifferent: [RuleComparisonDiff]
    let inBothSame: [String]
    let diff: YAMLConfigurationEngine.ConfigDiff

    var totalDifferences: Int {
        onlyInFirst.count + onlyInSecond.count + inBothDifferent.count
    }
}

/// Protocol for config comparison service
@MainActor
protocol ConfigComparisonServiceProtocol {
    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String
    ) throws -> ConfigComparisonResult
}

/// Service for comparing SwiftLint configurations from different workspaces
@MainActor
final class ConfigComparisonService: ConfigComparisonServiceProtocol {

    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String
    ) throws -> ConfigComparisonResult {
        let engine1 = YAMLConfigurationEngine(configPath: config1)
        let engine2 = YAMLConfigurationEngine(configPath: config2)
        try engine1.load()
        try engine2.load()

        let cfg1 = engine1.getConfig()
        let cfg2 = engine2.getConfig()

        let rules1 = Set(cfg1.rules.keys)
        let rules2 = Set(cfg2.rules.keys)

        let onlyInFirst = Array(rules1.subtracting(rules2)).sorted()
        let onlyInSecond = Array(rules2.subtracting(rules1)).sorted()

        let (inBothDifferent, inBothSame) = compareCommonRules(
            rules1.intersection(rules2), cfg1: cfg1, cfg2: cfg2,
            label1: label1, label2: label2
        )

        let content1 = (try? String(contentsOf: config1, encoding: .utf8)) ?? ""
        let content2 = (try? String(contentsOf: config2, encoding: .utf8)) ?? ""

        return ConfigComparisonResult(
            onlyInFirst: onlyInFirst,
            onlyInSecond: onlyInSecond,
            inBothDifferent: inBothDifferent,
            inBothSame: inBothSame,
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: onlyInSecond,
                removedRules: onlyInFirst,
                modifiedRules: inBothDifferent.map(\.ruleId),
                before: content1,
                after: content2
            )
        )
    }

    private func compareCommonRules(
        _ commonRules: Set<String>,
        cfg1: YAMLConfigurationEngine.YAMLConfig,
        cfg2: YAMLConfigurationEngine.YAMLConfig,
        label1: String,
        label2: String
    ) -> (different: [RuleComparisonDiff], same: [String]) {
        var different: [RuleComparisonDiff] = []
        var same: [String] = []

        for ruleId in commonRules.sorted() {
            let rc1 = cfg1.rules[ruleId]
            let rc2 = cfg2.rules[ruleId]

            if rc1 == rc2 {
                same.append(ruleId)
            } else {
                different.append(buildRuleDiff(
                    ruleId: ruleId, rc1: rc1, rc2: rc2,
                    label1: label1, label2: label2
                ))
            }
        }
        return (different, same)
    }

    private func buildRuleDiff(
        ruleId: String,
        rc1: RuleConfiguration?, rc2: RuleConfiguration?,
        label1: String, label2: String
    ) -> RuleComparisonDiff {
        var differences: [String] = []
        if rc1?.enabled != rc2?.enabled {
            let e1 = rc1?.enabled == true ? "enabled" : "disabled"
            let e2 = rc2?.enabled == true ? "enabled" : "disabled"
            differences.append("\(label1): \(e1), \(label2): \(e2)")
        }
        if rc1?.severity != rc2?.severity {
            let s1 = rc1?.severity?.rawValue ?? "default"
            let s2 = rc2?.severity?.rawValue ?? "default"
            differences.append("Severity: \(label1)=\(s1), \(label2)=\(s2)")
        }
        if rc1?.parameters != rc2?.parameters {
            differences.append("Parameters differ")
        }
        return RuleComparisonDiff(
            id: ruleId, ruleId: ruleId,
            firstConfig: rc1, secondConfig: rc2,
            differences: differences
        )
    }
}
