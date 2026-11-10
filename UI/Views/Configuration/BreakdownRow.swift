//
//  BreakdownRow.swift
//  SwiftLintRuleStudio
//
//  One metric of the configuration health breakdown
//

import SwiftLintRuleStudioCore
import SwiftUI

/// Row displaying a single breakdown metric
struct BreakdownRow: View {
    private let excellentThreshold = 80
    private let goodThreshold = 60
    private let fairThreshold = 40
    private let needsWorkThreshold = 20
    private let maxScore = 100

    let name: String
    let score: Int
    let weight: Int
    let description: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            // Progress bar
            progressBar
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var scoreColor: Color {
        switch score {
        case excellentThreshold...maxScore: return .green
        case goodThreshold..<excellentThreshold: return .blue
        case fairThreshold..<goodThreshold: return .yellow
        case needsWorkThreshold..<fairThreshold: return .orange
        default: return .red
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                    .clipShape(.rect(cornerRadius: 3))

                Rectangle()
                    .fill(scoreColor)
                    .frame(width: geometry.size.width * CGFloat(score) / CGFloat(maxScore), height: 6)
                    .clipShape(.rect(cornerRadius: 3))
            }
        }
        .frame(height: 6)
    }

    private var rowLabel: some View {
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
    }
}
