//
//  ConfigHealthScoreView.swift
//  SwiftLintRuleStudio
//
//  View for displaying detailed configuration health report
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The score ring, the grade and the one-line summary.
///
/// Takes the report. `ConfigHealthScoreView` is also handed `onApplyPreset`, an optional closure
/// the caller allocates on every update, so the view itself never compares equal — this does.
private struct ConfigHealthHeader: View {
    let report: ConfigHealthReport

    private var gradeColor: Color {
        switch report.grade {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .needsWork: return .orange
        case .poor: return .red
        }
    }

    private var healthSummary: String {
        switch report.grade {
        case .excellent:
            return "Your configuration is well optimized!"

        case .good:
            return "Good configuration with room for improvement."

        case .fair:
            return "Consider implementing the recommendations below."

        case .needsWork:
            return "Several areas need attention."

        case .poor:
            return "Significant improvements recommended."
        }
    }

    var body: some View {
        HStack(spacing: 24) {
            HealthScoreRing(report: report)

            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration Health")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(report.grade.displayName)
                    .font(.headline)
                    .foregroundStyle(gradeColor)

                Text(healthSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

/// Card displaying a single recommendation
private struct RecommendationCard: View {
    let recommendation: HealthRecommendation
    let onApplyPreset: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recommendation.title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text(recommendation.priority.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor.opacity(0.2))
                        .foregroundStyle(priorityColor)
                        .clipShape(.rect(cornerRadius: 4))
                }

                Text(recommendation.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                reviewPresetButton
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(priorityColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var priorityColor: Color {
        switch recommendation.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    @ViewBuilder
    private var reviewPresetButton: some View {
        if let presetId = recommendation.presetId,
           let onApplyPreset {
            Button {
                onApplyPreset(presetId)
            } label: {
                // Shows the preset's rules in the rule browser; it doesn't change
                // the configuration, so it isn't labelled "Apply".
                Label("Review Preset Rules", systemImage: "arrow.right.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Show this preset's rules in the rule list, where you can enable them")
            .controlSize(.small)
            .padding(.top, 4)
        }
    }
}

// MARK: - Health sections

/// Full health report view with score breakdown and recommendations
struct ConfigHealthScoreView: View {
    let report: ConfigHealthReport
    let onApplyPreset: ((String) -> Void)?

    init(report: ConfigHealthReport, onApplyPreset: ((String) -> Void)? = nil) {
        self.report = report
        self.onApplyPreset = onApplyPreset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with score
                ConfigHealthHeader(report: report)

                Divider()

                // Score breakdown
                HealthBreakdownSection(details: report.breakdown.details)

                Divider()

                // Recommendations
                if !report.recommendations.isEmpty {
                    recommendationsSection
                }
            }
            .padding()
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline)

            ForEach(report.recommendations) { recommendation in
                RecommendationCard(
                    recommendation: recommendation,
                    onApplyPreset: onApplyPreset
                )
            }
        }
    }
}

#Preview("Config Health Score View") {
    ConfigHealthScoreView(
        report: ConfigHealthReport(
            score: 72,
            grade: .fair,
            breakdown: ConfigHealthReport.ScoreBreakdown(
                rulesCoverage: 65,
                categoryBalance: 80,
                optInAdoption: 45,
                noDeprecatedRules: 100,
                pathConfiguration: 70
            ),
            recommendations: previewRecommendations()
        )
    ) { _ in
    }
    .frame(width: 500, height: 600)
}

/// A high- and a medium-priority recommendation for the score view's preview.
private func previewRecommendations() -> [HealthRecommendation] {
    [
        HealthRecommendation(
            priority: .high,
            title: "Configure Excluded Paths",
            description: "Add common paths like Pods, Carthage, or vendor to excluded",
            presetId: nil,
            actionType: .configureExcludes
        ),
        HealthRecommendation(
            priority: .medium,
            title: "Enable Recommended Opt-In Rules",
            description: "Consider enabling: first_where, sorted_first_last, empty_count",
            presetId: "performance",
            actionType: .enablePreset("performance")
        ),
    ]
}
