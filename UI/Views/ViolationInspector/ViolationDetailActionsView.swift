//
//  ViolationDetailActionsView.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ViolationDetailActionsView: View {
    let violation: Violation
    @Binding var showSuppressDialog: Bool
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                if !violation.suppressed {
                    Button {
                        showSuppressDialog = true
                    } label: {
                        Label("Suppress", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ViolationDetailSuppressButton")
                }

                if violation.resolvedAt == nil {
                    Button(action: onResolve) {
                        Label("Mark as Resolved", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
