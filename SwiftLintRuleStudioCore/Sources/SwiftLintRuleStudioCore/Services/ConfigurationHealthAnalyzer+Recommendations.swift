//
//  ConfigurationHealthAnalyzer+Recommendations.swift
//  SwiftLintRuleStudio
//
//  Recommendation generation for configuration health analysis
//

import Foundation

extension ConfigurationHealthAnalyzer {
    func generateRecommendations(
        config: YAMLConfigurationEngine.YAMLConfig,
        knownRules: [Rule],
        breakdown: ConfigHealthReport.ScoreBreakdown
    ) -> [HealthRecommendation] {
        var recommendations: [HealthRecommendation] = []

        appendOptInRecommendation(
            config: config, breakdown: breakdown,
            to: &recommendations
        )
        appendPathRecommendation(breakdown: breakdown, to: &recommendations)
        appendBalanceRecommendation(breakdown: breakdown, to: &recommendations)
        appendCoverageRecommendations(breakdown: breakdown, to: &recommendations)

        return recommendations
    }

    private func appendOptInRecommendation(
        config: YAMLConfigurationEngine.YAMLConfig,
        breakdown: ConfigHealthReport.ScoreBreakdown,
        to recommendations: inout [HealthRecommendation]
    ) {
        guard breakdown.optInAdoption < 50 else { return }
        let missingOptIn = recommendedOptInRules.subtracting(
            Set(config.optInRules ?? [])
        )
        guard !missingOptIn.isEmpty else { return }
        let ruleList = missingOptIn.prefix(3).joined(separator: ", ")
        recommendations.append(HealthRecommendation(
            priority: .medium,
            title: "Enable Recommended Opt-In Rules",
            description: "Consider enabling: \(ruleList)",
            presetId: "performance",
            actionType: .enablePreset("performance")
        ))
    }

    private func appendPathRecommendation(
        breakdown: ConfigHealthReport.ScoreBreakdown,
        to recommendations: inout [HealthRecommendation]
    ) {
        guard breakdown.pathConfiguration < 60 else { return }
        recommendations.append(HealthRecommendation(
            priority: .high,
            title: "Configure Excluded Paths",
            description: "Add common paths like Pods, Carthage, "
                + "or vendor to excluded",
            presetId: nil,
            actionType: .configureExcludes
        ))
    }

    private func appendBalanceRecommendation(
        breakdown: ConfigHealthReport.ScoreBreakdown,
        to recommendations: inout [HealthRecommendation]
    ) {
        guard breakdown.categoryBalance < 60 else { return }
        recommendations.append(HealthRecommendation(
            priority: .low,
            title: "Improve Category Coverage",
            description: "Consider enabling rules from "
                + "underrepresented categories",
            presetId: nil,
            actionType: .general
        ))
    }

    private func appendCoverageRecommendations(
        breakdown: ConfigHealthReport.ScoreBreakdown,
        to recommendations: inout [HealthRecommendation]
    ) {
        if breakdown.rulesCoverage < 30 {
            recommendations.append(HealthRecommendation(
                priority: .high,
                title: "Enable More Rules",
                description: "Your configuration has very few "
                    + "rules enabled",
                presetId: "code_style",
                actionType: .enablePreset("code_style")
            ))
        }

        if breakdown.rulesCoverage > 90 {
            recommendations.append(HealthRecommendation(
                priority: .low,
                title: "Consider Reducing Rules",
                description: "Having too many rules enabled "
                    + "might create noise",
                presetId: nil,
                actionType: .general
            ))
        }
    }
}
