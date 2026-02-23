//
//  ConfigHealthScoreView.swift
//  SwiftLintRuleStudio
//
//  View for displaying detailed configuration health report
//

import SwiftUI

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
                headerSection

                Divider()

                // Score breakdown
                breakdownSection

                Divider()

                // Recommendations
                if !report.recommendations.isEmpty {
                    recommendationsSection
                }
            }
            .padding()
        }
    }

    private var headerSection: some View {
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

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Breakdown")
                .font(.headline)

            ForEach(report.breakdown.details, id: \.name) { detail in
                BreakdownRow(
                    name: detail.name,
                    score: detail.score,
                    weight: detail.weight,
                    description: detail.description
                )
            }
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
}

/// Row displaying a single breakdown metric
struct BreakdownRow: View {
    let name: String
    let score: Int
    let weight: Int
    let description: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("(\(weight)%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isExpanded {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(score)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(scoreColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .clipShape(.rect(cornerRadius: 3))

                    Rectangle()
                        .fill(scoreColor)
                        .frame(width: geometry.size.width * CGFloat(score) / 100, height: 6)
                        .clipShape(.rect(cornerRadius: 3))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }
}

/// Card displaying a single recommendation
struct RecommendationCard: View {
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

                if let presetId = recommendation.presetId,
                   let onApplyPreset = onApplyPreset {
                    Button {
                        onApplyPreset(presetId)
                    } label: {
                        Label("Apply Preset", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
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
}

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Recommendations")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(report.recommendations.prefix(2)) { recommendation in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(priorityColor(for: recommendation))
                                .frame(width: 6, height: 6)

                            Text(recommendation.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
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
            recommendations: [
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
                )
            ]
        )
    ) { presetId in
        print("Apply preset: \(presetId)")
    }
    .frame(width: 500, height: 600)
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
                )
            ]
        ),
        onApplyPreset: nil
    )
}
