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

            // Snippets aren't read from the file yet; the placeholder below tells the user so.
            Text("Code snippet loading not yet implemented")
                .font(.body)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}
