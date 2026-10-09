//
//  RuleDocCodeBlock.swift
//  SwiftLintRuleStudio
//

import SwiftUI

/// A code block from a rule's documentation: full width, with one even background
/// behind the whole block rather than behind each line's text.
struct RuleDocCodeBlock: View {
    let code: AttributedString
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(code)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            // A light tint over the panel: lighter than the background in dark mode,
            // a soft gray in light mode.
            .background(
                colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05),
                in: .rect(cornerRadius: 6)
            )
    }
}
