//
//  HealthBreakdownSection.swift
//  SwiftLintRuleStudio
//
//  A section lifted out of ConfigHealthScoreView, which was at its file-length limit.
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The per-category score rows.
/// 
/// Takes the details, so it is untouched by anything else on the report.
struct HealthBreakdownSection: View {
    let details: [ConfigHealthReport.HealthScoreDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Breakdown")
                .font(.headline)

            ForEach(details, id: \.name) { detail in
                BreakdownRow(
                    name: detail.name,
                    score: detail.score,
                    weight: detail.weight,
                    description: detail.description
                )
            }
        }
    }
}
