//
//  ExplorerHelpView.swift
//  SwiftLintRuleStudio
//
//  In-app help for the sandboxed Explorer edition, opened from its Help menu.
//  Lives in the shared UI so the Studio-hosted unit tests can cover it.
//

import SwiftLintCLISeam
import SwiftLintRuleStudioCore
import SwiftUI

struct ExplorerHelpView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var swiftLintVersion: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(Bundle.main.appDisplayName) Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                section("Getting Started") {
                    Text("""
                    Click Open Workspace… and choose the folder that contains your Swift project. \
                    Browse the rule list to see what each rule does, simulate a rule to see how many \
                    violations it would produce, and preview your configuration changes before you save them.
                    """)
                }

                section("Built-In SwiftLint") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("""
                        \(Bundle.main.appDisplayName) runs its own copy of \(swiftLintName) inside the app, \
                        so there's nothing else to install. Your project's .swiftlint.yml is read and applied as usual.
                        """)
                        Text("""
                        For your security, apps from the Mac App Store run in a sandbox, which limits them to \
                        their own built-in tools instead of programs installed elsewhere on your Mac. That's why \
                        this app uses its bundled SwiftLint rather than one you've installed, and why its \
                        SwiftLint version updates along with the app.
                        """)
                    }
                }

                section("SourceKit Rules") {
                    Text("""
                    Rules that depend on SourceKit aren't checked in this app, because the sandbox doesn't \
                    allow it to use SourceKit. The rule list marks them \u{201C}Not checked in this app.\u{201D} \
                    You can still add them to your configuration.
                    """)
                }

                section("Using Your Own SwiftLint") {
                    Text("""
                    SwiftLint Rule Studio, the free non-sandboxed edition, uses the SwiftLint installed \
                    on your Mac, including SourceKit rules.
                    """)
                }

                section("More Help") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let reference = URL(string: "https://realm.github.io/SwiftLint/rule-directory.html") {
                            Link("SwiftLint Rule Reference", destination: reference)
                        }
                        if let issues = URL(string: "https://github.com/Joseph-Cursio/SwiftLintRuleStudio/issues") {
                            Link("Report an Issue", destination: issues)
                        }
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 480, minHeight: 420)
        .task { swiftLintVersion = try? await dependencies.swiftLintCLI.getVersion() }
    }

    private var swiftLintName: String {
        swiftLintVersion.map { "SwiftLint \($0)" } ?? "SwiftLint"
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            content()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ExplorerHelpView()
}
