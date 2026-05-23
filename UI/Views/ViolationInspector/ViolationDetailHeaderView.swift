//
//  ViolationDetailHeaderView.swift
//  SwiftLintRuleStudio
//

import LintStudioUI
import SwiftLintRuleStudioCore
import SwiftUI

struct ViolationDetailHeaderView: View {
    let violation: Violation
    @Environment(\.ruleRegistry) var ruleRegistry: RuleRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SeverityBadge(severity: violation.severity)

                if violation.suppressed {
                    Label("Suppressed", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if violation.resolvedAt != nil {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                Spacer()

                if let rule = ruleRegistry.rules.first(where: { $0.id == violation.ruleID }),
                   rule.supportsAutocorrection {
                    Label("Auto-fixable", systemImage: "wrench.and.screwdriver.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }

            Text("Rule: \(violation.ruleID)")
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}
