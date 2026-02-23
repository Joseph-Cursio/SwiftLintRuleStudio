//
//  ConfigurationHealthAnalyzer.swift
//  SwiftLintRuleStudio
//
//  Service for analyzing SwiftLint configuration health and generating reports
//

import Foundation

/// Health grade based on configuration score
enum HealthGrade: String, CaseIterable, Sendable {
    case excellent = "A"
    case good = "B"
    case fair = "C"
    case needsWork = "D"
    case poor = "F"

    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .needsWork: return "Needs Work"
        case .poor: return "Poor"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .needsWork: return "orange"
        case .poor: return "red"
        }
    }

    static func from(score: Int) -> HealthGrade {
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
struct ConfigHealthReport: Identifiable, Sendable {
    let id = UUID()
    let score: Int
    let grade: HealthGrade
    let breakdown: ScoreBreakdown
    let recommendations: [HealthRecommendation]

    struct ScoreBreakdown: Sendable {
        let rulesCoverage: Int       // 40% weight - enabled rules / total rules
        let categoryBalance: Int     // 20% weight - coverage across categories
        let optInAdoption: Int       // 15% weight - opted-in recommended rules
        let noDeprecatedRules: Int   // 10% weight - no deprecated rules
        let pathConfiguration: Int   // 15% weight - proper excludes set up

        var details: [(name: String, score: Int, weight: Int, description: String)] {
            [
                ("Rules Coverage", rulesCoverage, 40, "Percentage of rules enabled"),
                ("Category Balance", categoryBalance, 20, "Coverage across rule categories"),
                ("Opt-In Adoption", optInAdoption, 15, "Recommended opt-in rules enabled"),
                ("No Deprecated Rules", noDeprecatedRules, 10, "Avoiding deprecated rules"),
                ("Path Configuration", pathConfiguration, 15, "Proper include/exclude paths")
            ]
        }
    }
}

/// A recommendation for improving configuration health
struct HealthRecommendation: Identifiable, Sendable {
    let id = UUID()
    let priority: Priority
    let title: String
    let description: String
    let presetId: String?
    let actionType: ActionType

    enum Priority: String, CaseIterable, Comparable, Sendable {
        case high
        case medium
        case low

        var displayName: String {
            rawValue.capitalized
        }

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.high, .medium, .low]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    enum ActionType: Sendable {
        case enablePreset(String)
        case enableRule(String)
        case disableRule(String)
        case configureExcludes
        case general
    }
}

/// Protocol for analyzing configuration health
@MainActor
protocol ConfigurationHealthAnalyzerProtocol {
    /// Analyze a configuration and return a health report
    func analyze(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule]
    ) -> ConfigHealthReport
}

/// Service for analyzing SwiftLint configuration health
@MainActor
class ConfigurationHealthAnalyzer: ConfigurationHealthAnalyzerProtocol {
    private let recommendedOptInRules: Set<String> = [
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

    func analyze(
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

    private func generateRecommendations(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule],
        breakdown: ConfigHealthReport.ScoreBreakdown
    ) -> [HealthRecommendation] {
        var recommendations: [HealthRecommendation] = []

        // Low opt-in adoption
        if breakdown.optInAdoption < 50 {
            let missingOptIn = recommendedOptInRules.subtracting(Set(config.optInRules ?? []))
            if !missingOptIn.isEmpty {
                recommendations.append(HealthRecommendation(
                    priority: .medium,
                    title: "Enable Recommended Opt-In Rules",
                    description: "Consider enabling: \(missingOptIn.prefix(3).joined(separator: ", "))",
                    presetId: "performance",
                    actionType: .enablePreset("performance")
                ))
            }
        }

        // Poor path configuration
        if breakdown.pathConfiguration < 60 {
            recommendations.append(HealthRecommendation(
                priority: .high,
                title: "Configure Excluded Paths",
                description: "Add common paths like Pods, Carthage, or vendor to excluded",
                presetId: nil,
                actionType: .configureExcludes
            ))
        }

        // Low category balance
        if breakdown.categoryBalance < 60 {
            recommendations.append(HealthRecommendation(
                priority: .low,
                title: "Improve Category Coverage",
                description: "Consider enabling rules from underrepresented categories",
                presetId: nil,
                actionType: .general
            ))
        }

        // Very low rules coverage
        if breakdown.rulesCoverage < 30 {
            recommendations.append(HealthRecommendation(
                priority: .high,
                title: "Enable More Rules",
                description: "Your configuration has very few rules enabled",
                presetId: "code_style",
                actionType: .enablePreset("code_style")
            ))
        }

        // Very high rules coverage (might be too noisy)
        if breakdown.rulesCoverage > 90 {
            recommendations.append(HealthRecommendation(
                priority: .low,
                title: "Consider Reducing Rules",
                description: "Having too many rules enabled might create noise",
                presetId: nil,
                actionType: .general
            ))
        }

        return recommendations
    }
}
