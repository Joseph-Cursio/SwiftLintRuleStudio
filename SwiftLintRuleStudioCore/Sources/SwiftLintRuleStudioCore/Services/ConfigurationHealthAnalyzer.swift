//
//  ConfigurationHealthAnalyzer.swift
//  SwiftLintRuleStudio
//
//  Service for analyzing SwiftLint configuration health and generating reports
//

import Foundation

/// Health grade based on configuration score
public enum HealthGrade: String, CaseIterable, Sendable {
    case excellent = "A"
    case good = "B"
    case fair = "C"
    case needsWork = "D"
    case poor = "F"

    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .needsWork: return "Needs Work"
        case .poor: return "Poor"
        }
    }

    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .needsWork: return "orange"
        case .poor: return "red"
        }
    }

    public static func from(score: Int) -> HealthGrade {
        switch score {
        case 90...100: return .excellent
        case 75..<90: return .good
        case 60..<75: return .fair
        case 40..<60: return .needsWork
        default: return .poor
        }
    }
}

/// A health report for a SwiftLint configuration
public struct ConfigHealthReport: Identifiable, Sendable {
    public let id = UUID()
    public let score: Int
    public let grade: HealthGrade
    public let breakdown: ScoreBreakdown
    public let recommendations: [HealthRecommendation]

    public init(score: Int, grade: HealthGrade, breakdown: ScoreBreakdown, recommendations: [HealthRecommendation]) {
        self.score = score
        self.grade = grade
        self.breakdown = breakdown
        self.recommendations = recommendations
    }

    public struct HealthScoreDetail: Sendable {
        public let name: String
        public let score: Int
        public let weight: Int
        public let description: String

        public init(name: String, score: Int, weight: Int, description: String) {
            self.name = name
            self.score = score
            self.weight = weight
            self.description = description
        }
    }

    public struct ScoreBreakdown: Sendable {
        public let rulesCoverage: Int
        public let categoryBalance: Int
        public let optInAdoption: Int
        public let noDeprecatedRules: Int
        public let pathConfiguration: Int

        public init(
            rulesCoverage: Int,
            categoryBalance: Int,
            optInAdoption: Int,
            noDeprecatedRules: Int,
            pathConfiguration: Int
        ) {
            self.rulesCoverage = rulesCoverage
            self.categoryBalance = categoryBalance
            self.optInAdoption = optInAdoption
            self.noDeprecatedRules = noDeprecatedRules
            self.pathConfiguration = pathConfiguration
        }

        public var details: [HealthScoreDetail] {
            [
                HealthScoreDetail(
                    name: "Rules Coverage", score: rulesCoverage,
                    weight: 40, description: "Percentage of rules enabled"),
                HealthScoreDetail(
                    name: "Category Balance", score: categoryBalance,
                    weight: 20, description: "Coverage across rule categories"),
                HealthScoreDetail(
                    name: "Opt-In Adoption", score: optInAdoption,
                    weight: 15, description: "Recommended opt-in rules enabled"),
                HealthScoreDetail(
                    name: "No Deprecated Rules", score: noDeprecatedRules,
                    weight: 10, description: "Avoiding deprecated rules"),
                HealthScoreDetail(
                    name: "Path Configuration", score: pathConfiguration,
                    weight: 15, description: "Proper include/exclude paths")
            ]
        }
    }
}

/// A recommendation for improving configuration health
public struct HealthRecommendation: Identifiable, Sendable {
    public let id = UUID()
    public let priority: Priority
    public let title: String
    public let description: String
    public let presetId: String?
    public let actionType: ActionType

    public init(priority: Priority, title: String, description: String, presetId: String?, actionType: ActionType) {
        self.priority = priority
        self.title = title
        self.description = description
        self.presetId = presetId
        self.actionType = actionType
    }

    public enum Priority: String, CaseIterable, Comparable, Sendable {
        case high
        case medium
        case low

        public var displayName: String {
            rawValue.capitalized
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.high, .medium, .low]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    public enum ActionType: Sendable {
        case enablePreset(String)
        case enableRule(String)
        case disableRule(String)
        case configureExcludes
        case general
    }
}

/// Protocol for analyzing configuration health
public protocol ConfigurationHealthAnalyzerProtocol {
    /// Analyze a configuration and return a health report
    func analyze(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> ConfigHealthReport
}

/// Service for analyzing SwiftLint configuration health
public class ConfigurationHealthAnalyzer: ConfigurationHealthAnalyzerProtocol {
    let recommendedOptInRules: Set<String> = [
        "explicit_init",
        "first_where",
        "joined_default_parameter",
        "redundant_nil_coalescing",
        "sorted_first_last",
        "contains_over_first_not_nil",
        "empty_count",
        "empty_string",
        "flatmap_over_map_reduce",
        "last_where",
        "modifier_order",
        "reduce_into"
    ]

    private let deprecatedRules: Set<String> = [
        // These are examples - in real usage, fetch from SwiftLint CLI
    ]

    public func analyze(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> ConfigHealthReport {
        let breakdown = calculateBreakdown(config: config, knownRules: knownRules)
        let score = calculateTotalScore(breakdown: breakdown)
        let grade = HealthGrade.from(score: score)
        let recommendations = generateRecommendations(
            config: config,
            knownRules: knownRules,
            breakdown: breakdown
        )

        return ConfigHealthReport(
            score: score,
            grade: grade,
            breakdown: breakdown,
            recommendations: recommendations.sorted { $0.priority < $1.priority }
        )
    }

    // MARK: - Private Methods

    private func calculateBreakdown(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> ConfigHealthReport.ScoreBreakdown {
        let rulesCoverage = calculateRulesCoverage(config: config, knownRules: knownRules)
        let categoryBalance = calculateCategoryBalance(config: config, knownRules: knownRules)
        let optInAdoption = calculateOptInAdoption(config: config)
        let noDeprecatedRules = calculateNoDeprecatedRules(config: config)
        let pathConfiguration = calculatePathConfiguration(config: config)

        return ConfigHealthReport.ScoreBreakdown(
            rulesCoverage: rulesCoverage,
            categoryBalance: categoryBalance,
            optInAdoption: optInAdoption,
            noDeprecatedRules: noDeprecatedRules,
            pathConfiguration: pathConfiguration
        )
    }

    private func calculateTotalScore(breakdown: ConfigHealthReport.ScoreBreakdown) -> Int {
        let weighted = Double(breakdown.rulesCoverage) * 0.40 +
            Double(breakdown.categoryBalance) * 0.20 +
            Double(breakdown.optInAdoption) * 0.15 +
            Double(breakdown.noDeprecatedRules) * 0.10 +
            Double(breakdown.pathConfiguration) * 0.15

        return Int(weighted.rounded())
    }

    private func calculateRulesCoverage(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> Int {
        guard !knownRules.isEmpty else { return 50 }

        // Count enabled rules
        let enabledRuleIds = Set(config.rules.filter { $0.value.enabled }.keys)
        let optInRuleIds = Set(config.optInRules ?? [])
        let disabledRuleIds = Set(config.disabledRules ?? [])

        // Default enabled rules (non-opt-in that aren't disabled)
        let defaultEnabledCount = knownRules.filter { !$0.isOptIn && !disabledRuleIds.contains($0.id) }.count
        let explicitlyEnabledCount = enabledRuleIds.count + optInRuleIds.count

        let totalEnabled = defaultEnabledCount + explicitlyEnabledCount
        let coverage = Double(totalEnabled) / Double(knownRules.count)

        // Target is around 40-60% of rules enabled (too many can be noisy)
        let optimalCoverage = min(coverage / 0.5, 1.0)
        return Int(optimalCoverage * 100)
    }

    private func calculateCategoryBalance(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> Int {
        guard !knownRules.isEmpty else { return 50 }

        let disabledRuleIds = Set(config.disabledRules ?? [])
        let optInRuleIds = Set(config.optInRules ?? [])

        // Group rules by category and check if each category has coverage
        let rulesByCategory = Dictionary(grouping: knownRules) { $0.category }

        var categoriesWithCoverage = 0
        for (_, rules) in rulesByCategory {
            let enabledInCategory = rules.filter { rule in
                if rule.isOptIn {
                    return optInRuleIds.contains(rule.id)
                } else {
                    return !disabledRuleIds.contains(rule.id)
                }
            }
            if !enabledInCategory.isEmpty {
                categoriesWithCoverage += 1
            }
        }

        let balance = Double(categoriesWithCoverage) / Double(RuleCategory.allCases.count)
        return Int(balance * 100)
    }

    private func calculateOptInAdoption(config: YAMLConfigurationEngine.YAMLConfig) -> Int {
        let optInRuleIds = Set(config.optInRules ?? [])
        let enabledRecommended = optInRuleIds.intersection(recommendedOptInRules)

        if recommendedOptInRules.isEmpty { return 100 }

        let adoption = Double(enabledRecommended.count) / Double(recommendedOptInRules.count)
        return Int(adoption * 100)
    }

    private func calculateNoDeprecatedRules(config: YAMLConfigurationEngine.YAMLConfig) -> Int {
        let allConfiguredRules = Set(config.rules.keys)
            .union(Set(config.optInRules ?? []))
            .union(Set(config.disabledRules ?? []))

        let usedDeprecated = allConfiguredRules.intersection(deprecatedRules)

        if deprecatedRules.isEmpty { return 100 }
        if usedDeprecated.isEmpty { return 100 }

        let penalty = Double(usedDeprecated.count) / Double(deprecatedRules.count)
        return Int((1.0 - penalty) * 100)
    }

    private func calculatePathConfiguration(config: YAMLConfigurationEngine.YAMLConfig) -> Int {
        var score = 50 // Base score

        // Has excluded paths configured
        if let excluded = config.excluded, !excluded.isEmpty {
            score += 25

            // Common patterns are excluded
            let commonExcludes = ["Pods", "Carthage", "vendor", "build", ".build"]
            let hasCommonExcludes = commonExcludes.contains { pattern in
                excluded.contains { $0.contains(pattern) }
            }
            if hasCommonExcludes {
                score += 15
            }
        }

        // Has included paths configured (focused linting)
        if let included = config.included, !included.isEmpty {
            score += 10
        }

        return min(score, 100)
    }

}
