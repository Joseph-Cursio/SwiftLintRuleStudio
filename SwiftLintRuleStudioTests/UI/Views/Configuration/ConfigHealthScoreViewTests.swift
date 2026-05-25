//
//  ConfigHealthScoreViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for ConfigHealthScoreView. Construct a
//  ConfigHealthReport in-memory and assert the three top-level section
//  headers (Configuration Health / Score Breakdown / Recommendations)
//  render.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ConfigHealthScoreViewTests {
    @Test("ConfigHealthScoreView renders the three section headers")
    func testRendersSectionHeaders() async throws {
        // The Recommendations section only renders when there's at least one
        // recommendation, so provide one so the test can assert that section's
        // header along with the always-present Configuration Health and Score
        // Breakdown headers.
        let report = ConfigHealthReport(
            score: 80,
            grade: .good,
            breakdown: ConfigHealthReport.ScoreBreakdown(
                rulesCoverage: 80,
                categoryBalance: 75,
                optInAdoption: 70,
                noDeprecatedRules: 100,
                pathConfiguration: 70
            ),
            recommendations: [
                HealthRecommendation(
                    priority: .medium,
                    title: "Enable opt-in rules",
                    description: "Opt-in rules catch additional issues.",
                    presetId: nil,
                    actionType: .enableRule("force_cast")
                )
            ]
        )
        let view = await MainActor.run {
            ConfigHealthScoreView(report: report)
        }

        let (hasHeader, hasBreakdown, hasRecs) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Configuration Health")) != nil,
                (try? inspector.find(text: "Score Breakdown")) != nil,
                (try? inspector.find(text: "Recommendations")) != nil
            )
        }

        #expect(hasHeader)
        #expect(hasBreakdown)
        #expect(hasRecs)
    }
}
