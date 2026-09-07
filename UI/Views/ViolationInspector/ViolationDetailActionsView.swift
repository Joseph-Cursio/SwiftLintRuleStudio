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
                    // A single store into a `@Binding` the parent owns and a test supplies, so
                    // the effect is already reachable; naming it would produce a method whose
                    // whole content is the store. `Unreachable Effect Closure` reports it because
                    // a bare assignment is not a member setter — the one shape where its
                    // single-store gate cannot see that the seam already exists.
                    // swiftprojectlint:disable:next unreachable-effect-closure
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
