//
//  ViolationDetailMessageView.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ViolationDetailMessageView: View {
    let violation: Violation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)

            Text(violation.message)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
