//
//  ConfigHealthPopover.swift
//  SwiftLintRuleStudio
//
//  Compact popover version of the configuration health score
//

import SwiftLintRuleStudioCore
import SwiftUI

/// Compact popover version of health score
struct ConfigHealthPopover: View {
    let report: ConfigHealthReport
    let onApplyPreset: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HealthScoreRing(report: report)
                    .scaleEffect(0.7)
                    .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Health Score")
                        .font(.headline)

                    Text(report.grade.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !report.recommendations.isEmpty {
                Divider()

                topRecommendations
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func priorityColor(for recommendation: HealthRecommendation) -> Color {
        switch recommendation.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private var topRecommendations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Recommendations")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(report.recommendations.prefix(2)) { recommendation in
                HStack(spacing: 8) {
                    Circle()
                        .fill(priorityColor(for: recommendation))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)

                    Text(recommendation.priority.displayName)
                        .font(.caption2)
                        .foregroundStyle(priorityColor(for: recommendation))

                    Text(recommendation.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview("Config Health Popover") {
    ConfigHealthPopover(
        report: ConfigHealthReport(
            score: 85,
            grade: .good,
            breakdown: ConfigHealthReport.ScoreBreakdown(
                rulesCoverage: 80,
                categoryBalance: 90,
                optInAdoption: 75,
                noDeprecatedRules: 100,
                pathConfiguration: 85
            ),
            recommendations: [
                HealthRecommendation(
                    priority: .medium,
                    title: "Enable More Opt-In Rules",
                    description: "Consider enabling performance rules",
                    presetId: "performance",
                    actionType: .enablePreset("performance")
                ),
            ]
        ),
        onApplyPreset: nil
    )
}
