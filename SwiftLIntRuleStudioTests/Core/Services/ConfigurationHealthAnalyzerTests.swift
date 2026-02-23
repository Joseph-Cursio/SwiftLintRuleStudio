//
//  ConfigurationHealthAnalyzerTests.swift
//  SwiftLintRuleStudioTests
//
//  Unit tests for ConfigurationHealthAnalyzer
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct ConfigurationHealthAnalyzerTests {
    // MARK: - Test Helpers

    private func createRule(
        id: String,
        category: RuleCategory = .style,
        isOptIn: Bool = false
    ) -> Rule {
        Rule(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Test rule",
            category: category,
            isOptIn: isOptIn,
            severity: .warning,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil
        )
    }

    // MARK: - Basic Analysis Tests

    @Test("Analyzer returns valid report for empty config")
    func testAnalyzesEmptyConfig() {
        let analyzer = ConfigurationHealthAnalyzer()
        let config = YAMLConfigurationEngine.YAMLConfig()
        let report = analyzer.analyze(config: config, knownRules: [])

        #expect(report.score >= 0 && report.score <= 100)
        #expect(HealthGrade.allCases.contains(report.grade))
    }

    @Test("Analyzer returns higher score for well-configured project")
    func testHighScoreForWellConfiguredProject() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.excluded = ["Pods", "Carthage", "vendor"]
        config.optInRules = [
            "first_where",
            "sorted_first_last",
            "empty_count",
            "reduce_into"
        ]

        let rules = [
            createRule(id: "force_cast", category: .lint),
            createRule(id: "line_length", category: .metrics),
            createRule(id: "trailing_whitespace", category: .style),
            createRule(id: "first_where", category: .performance, isOptIn: true),
            createRule(id: "sorted_first_last", category: .performance, isOptIn: true),
            createRule(id: "empty_count", category: .performance, isOptIn: true),
            createRule(id: "reduce_into", category: .performance, isOptIn: true)
        ]

        let report = analyzer.analyze(config: config, knownRules: rules)

        #expect(report.score >= 60)
    }

    @Test("Analyzer returns lower score for poor configuration")
    func testLowScoreForPoorConfiguration() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        // No excluded paths, no opt-in rules, many rules disabled
        config.disabledRules = [
            "force_cast",
            "line_length",
            "trailing_whitespace"
        ]

        let rules = [
            createRule(id: "force_cast", category: .lint),
            createRule(id: "line_length", category: .metrics),
            createRule(id: "trailing_whitespace", category: .style),
            createRule(id: "first_where", category: .performance, isOptIn: true)
        ]

        let report = analyzer.analyze(config: config, knownRules: rules)

        #expect(report.score < 80)
    }

    // MARK: - Grade Tests

    @Test("HealthGrade.from returns correct grades")
    func testHealthGradeFromScore() {
        #expect(HealthGrade.from(score: 100) == .excellent)
        #expect(HealthGrade.from(score: 95) == .excellent)
        #expect(HealthGrade.from(score: 90) == .excellent)
        #expect(HealthGrade.from(score: 89) == .good)
        #expect(HealthGrade.from(score: 75) == .good)
        #expect(HealthGrade.from(score: 74) == .fair)
        #expect(HealthGrade.from(score: 60) == .fair)
        #expect(HealthGrade.from(score: 59) == .needsWork)
        #expect(HealthGrade.from(score: 40) == .needsWork)
        #expect(HealthGrade.from(score: 39) == .poor)
        #expect(HealthGrade.from(score: 0) == .poor)
    }

    @Test("HealthGrade has display names")
    func testHealthGradeDisplayNames() {
        #expect(HealthGrade.excellent.displayName == "Excellent")
        #expect(HealthGrade.good.displayName == "Good")
        #expect(HealthGrade.fair.displayName == "Fair")
        #expect(HealthGrade.needsWork.displayName == "Needs Work")
        #expect(HealthGrade.poor.displayName == "Poor")
    }

    // MARK: - Score Breakdown Tests

    @Test("Score breakdown includes all components")
    func testScoreBreakdownComponents() {
        let analyzer = ConfigurationHealthAnalyzer()
        let config = YAMLConfigurationEngine.YAMLConfig()
        let report = analyzer.analyze(config: config, knownRules: [])

        let details = report.breakdown.details
        #expect(details.count == 5)

        let names = details.map(\.name)
        #expect(names.contains("Rules Coverage"))
        #expect(names.contains("Category Balance"))
        #expect(names.contains("Opt-In Adoption"))
        #expect(names.contains("No Deprecated Rules"))
        #expect(names.contains("Path Configuration"))
    }

    @Test("Score breakdown weights sum to 100")
    func testScoreBreakdownWeights() {
        let analyzer = ConfigurationHealthAnalyzer()
        let config = YAMLConfigurationEngine.YAMLConfig()
        let report = analyzer.analyze(config: config, knownRules: [])

        let totalWeight = report.breakdown.details.reduce(0) { $0 + $1.weight }
        #expect(totalWeight == 100)
    }

    @Test("Path configuration score improves with excluded paths")
    func testPathConfigurationScore() {
        let analyzer = ConfigurationHealthAnalyzer()

        let configWithout = YAMLConfigurationEngine.YAMLConfig()
        let reportWithout = analyzer.analyze(config: configWithout, knownRules: [])

        var configWith = YAMLConfigurationEngine.YAMLConfig()
        configWith.excluded = ["Pods", "Carthage"]
        let reportWith = analyzer.analyze(config: configWith, knownRules: [])

        #expect(reportWith.breakdown.pathConfiguration > reportWithout.breakdown.pathConfiguration)
    }

    // MARK: - Recommendations Tests

    @Test("Generates recommendations for poor configuration")
    func testGeneratesRecommendations() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        // Poor config: no excludes, no opt-in rules
        config.disabledRules = ["force_cast", "line_length"]

        let rules = [
            createRule(id: "force_cast"),
            createRule(id: "line_length"),
            createRule(id: "first_where", isOptIn: true)
        ]

        let report = analyzer.analyze(config: config, knownRules: rules)

        #expect(!report.recommendations.isEmpty)
    }

    @Test("Recommendations are sorted by priority")
    func testRecommendationsSortedByPriority() {
        let analyzer = ConfigurationHealthAnalyzer()
        let config = YAMLConfigurationEngine.YAMLConfig()
        // Trigger multiple recommendations

        let rules = [
            createRule(id: "force_cast"),
            createRule(id: "first_where", isOptIn: true)
        ]

        let report = analyzer.analyze(config: config, knownRules: rules)

        // Verify recommendations are sorted (high before medium before low)
        var previousPriority: HealthRecommendation.Priority?
        for recommendation in report.recommendations {
            if let prev = previousPriority {
                #expect(prev <= recommendation.priority)
            }
            previousPriority = recommendation.priority
        }
    }

    @Test("Recommendation priority comparison works correctly")
    func testRecommendationPriorityComparison() {
        #expect(HealthRecommendation.Priority.high < HealthRecommendation.Priority.medium)
        #expect(HealthRecommendation.Priority.medium < HealthRecommendation.Priority.low)
        #expect(HealthRecommendation.Priority.high < HealthRecommendation.Priority.low)
    }

    // MARK: - ConfigHealthReport Tests

    @Test("ConfigHealthReport has unique ID")
    func testConfigHealthReportHasUniqueId() {
        let analyzer = ConfigurationHealthAnalyzer()
        let config = YAMLConfigurationEngine.YAMLConfig()

        let report1 = analyzer.analyze(config: config, knownRules: [])
        let report2 = analyzer.analyze(config: config, knownRules: [])

        #expect(report1.id != report2.id)
    }

    // MARK: - HealthRecommendation Tests

    @Test("HealthRecommendation has unique ID")
    func testHealthRecommendationHasUniqueId() {
        let rec1 = HealthRecommendation(
            priority: .high,
            title: "Test",
            description: "Test",
            presetId: nil,
            actionType: .general
        )
        let rec2 = HealthRecommendation(
            priority: .high,
            title: "Test",
            description: "Test",
            presetId: nil,
            actionType: .general
        )

        #expect(rec1.id != rec2.id)
    }

    @Test("HealthRecommendation.Priority has display names")
    func testRecommendationPriorityDisplayNames() {
        #expect(HealthRecommendation.Priority.high.displayName == "High")
        #expect(HealthRecommendation.Priority.medium.displayName == "Medium")
        #expect(HealthRecommendation.Priority.low.displayName == "Low")
    }

    // MARK: - Category Balance Tests

    @Test("Category balance improves with rules across categories")
    func testCategoryBalance() {
        let analyzer = ConfigurationHealthAnalyzer()

        // Single category
        let config1 = YAMLConfigurationEngine.YAMLConfig()
        let rules1 = [
            createRule(id: "rule1", category: .style),
            createRule(id: "rule2", category: .style)
        ]
        let report1 = analyzer.analyze(config: config1, knownRules: rules1)

        // Multiple categories
        let config2 = YAMLConfigurationEngine.YAMLConfig()
        let rules2 = [
            createRule(id: "rule1", category: .style),
            createRule(id: "rule2", category: .lint),
            createRule(id: "rule3", category: .metrics),
            createRule(id: "rule4", category: .performance),
            createRule(id: "rule5", category: .idiomatic)
        ]
        let report2 = analyzer.analyze(config: config2, knownRules: rules2)

        #expect(report2.breakdown.categoryBalance > report1.breakdown.categoryBalance)
    }

    // MARK: - Opt-In Adoption Tests

    @Test("Opt-in adoption improves with recommended rules enabled")
    func testOptInAdoption() {
        let analyzer = ConfigurationHealthAnalyzer()

        let config1 = YAMLConfigurationEngine.YAMLConfig()
        let report1 = analyzer.analyze(config: config1, knownRules: [])

        var config2 = YAMLConfigurationEngine.YAMLConfig()
        config2.optInRules = ["first_where", "sorted_first_last", "empty_count", "reduce_into"]
        let report2 = analyzer.analyze(config: config2, knownRules: [])

        #expect(report2.breakdown.optInAdoption > report1.breakdown.optInAdoption)
    }
}
