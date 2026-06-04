//
//  CustomRuleConflictBanner.swift
//  SwiftLintRuleStudio
//
//  Advisory banner shown in the Config Map inspector when the selected config
//  defines a custom rule whose name collides with a built-in SwiftLint rule.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct CustomRuleConflictBanner: View {
    let conflicts: [CustomRuleConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conflicts) { conflict in
                Label {
                    Text(conflict.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("ConfigMapCustomRuleConflict")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
    }
}
