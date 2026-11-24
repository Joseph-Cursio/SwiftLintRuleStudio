//
//  RuleCategoryColors.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

enum RuleCategoryColors {
    static func color(for category: RuleCategory) -> Color {
        switch category {
        case .style: .blue
        case .lint: .red
        case .metrics: .purple
        case .performance: .orange
        case .idiomatic: .green
        }
    }
}
