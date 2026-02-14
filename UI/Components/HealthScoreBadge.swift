//
//  HealthScoreBadge.swift
//  SwiftLintRuleStudio
//
//  Badge component for displaying configuration health score
//

import SwiftUI

/// Compact badge showing the health score
struct HealthScoreBadge: View {
    let report: ConfigHealthReport
    let showGrade: Bool

    init(report: ConfigHealthReport, showGrade: Bool = true) {
        self.report = report
        self.showGrade = showGrade
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gradeColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(gradeColor.opacity(0.3), lineWidth: 2)
                )

            if showGrade {
                Text(report.grade.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundColor(gradeColor)
            }

            Text("\(report.score)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(gradeColor.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(gradeColor.opacity(0.3), lineWidth: 1)
        )
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
}

/// Larger health score display with ring chart
struct HealthScoreRing: View {
    let report: ConfigHealthReport
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 12)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    gradeColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animatedProgress)

            // Center content
            VStack(spacing: 4) {
                Text(report.grade.rawValue)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(gradeColor)

                Text("\(report.score)/100")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 100, height: 100)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = Double(report.score) / 100.0
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
}

/// Mini inline health indicator
struct HealthScoreIndicator: View {
    let grade: HealthGrade

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(gradeColor)
                .frame(width: 8, height: 8)

            Text(grade.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var gradeColor: Color {
        switch grade {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .needsWork: return .orange
        case .poor: return .red
        }
    }
}

#Preview("Health Score Badge") {
    VStack(spacing: 16) {
        ForEach([100, 85, 70, 55, 30], id: \.self) { score in
            HealthScoreBadge(
                report: ConfigHealthReport(
                    score: score,
                    grade: HealthGrade.from(score: score),
                    breakdown: ConfigHealthReport.ScoreBreakdown(
                        rulesCoverage: score,
                        categoryBalance: score,
                        optInAdoption: score,
                        noDeprecatedRules: 100,
                        pathConfiguration: score
                    ),
                    recommendations: []
                )
            )
        }
    }
    .padding()
}

#Preview("Health Score Ring") {
    HStack(spacing: 32) {
        HealthScoreRing(
            report: ConfigHealthReport(
                score: 92,
                grade: .excellent,
                breakdown: ConfigHealthReport.ScoreBreakdown(
                    rulesCoverage: 90,
                    categoryBalance: 95,
                    optInAdoption: 90,
                    noDeprecatedRules: 100,
                    pathConfiguration: 85
                ),
                recommendations: []
            )
        )

        HealthScoreRing(
            report: ConfigHealthReport(
                score: 45,
                grade: .needsWork,
                breakdown: ConfigHealthReport.ScoreBreakdown(
                    rulesCoverage: 40,
                    categoryBalance: 50,
                    optInAdoption: 30,
                    noDeprecatedRules: 100,
                    pathConfiguration: 50
                ),
                recommendations: []
            )
        )
    }
    .padding()
}

#Preview("Health Score Indicator") {
    VStack(spacing: 8) {
        ForEach(HealthGrade.allCases, id: \.self) { grade in
            HealthScoreIndicator(grade: grade)
        }
    }
    .padding()
}
