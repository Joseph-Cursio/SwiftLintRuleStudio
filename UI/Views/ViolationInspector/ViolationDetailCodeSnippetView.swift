//
//  ViolationDetailCodeSnippetView.swift
//  SwiftLintRuleStudio
//

import SwiftUI

struct ViolationDetailCodeSnippetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Context")
                .font(.headline)

            // TODO: Load and display code snippet from file
            Text("Code snippet loading not yet implemented")
                .font(.body)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}
