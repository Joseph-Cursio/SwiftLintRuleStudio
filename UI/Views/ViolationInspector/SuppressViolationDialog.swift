//
//  SuppressViolationDialog.swift
//  SwiftLintRuleStudio
//
//  Sheet for capturing a suppression reason before suppressing a violation
//

import SwiftUI

struct SuppressViolationDialog: View {
    @Binding var reason: String
    let onSuppress: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField("Reason (optional)", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Suppression Reason")
                } footer: {
                    Text("Provide a reason for suppressing this violation. This helps with code review and maintenance.")
                }
            }
            .navigationTitle("Suppress Violation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Suppress") {
                        onSuppress(reason.isEmpty ? "Suppressed via Violation Inspector" : reason)
                    }
                }
            }
        }
        .frame(width: 500, height: 300)
    }
}
