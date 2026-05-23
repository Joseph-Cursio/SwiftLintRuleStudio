//
//  ViolationDetailLocationView.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ViolationDetailLocationView: View {
    let violation: Violation
    @Binding var isOpeningInXcode: Bool
    let openInXcode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)
            locationDetails
            openInXcodeButton
        }
    }

    private var locationDetails: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(violation.filePath)
                    .font(.body)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(violation.line)")
                    .font(.body)
            }

            if let column = violation.column {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Column")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(column)")
                        .font(.body)
                }
            }
        }
    }

    private var openInXcodeButton: some View {
        Button(action: openInXcode) {
            if isOpeningInXcode {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Label("Open in Xcode", systemImage: "arrow.right.circle")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isOpeningInXcode)
        .accessibilityLabel("Open in Xcode")
        .accessibilityIdentifier("ViolationDetailOpenInXcodeButton")
    }
}
