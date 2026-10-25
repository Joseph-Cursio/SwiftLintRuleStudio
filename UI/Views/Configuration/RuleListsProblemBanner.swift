//
//  RuleListsProblemBanner.swift
//  SwiftLintRuleStudio
//
//  Warns when the workspace's `.swiftlint.yml` combines rule lists SwiftLint
//  mishandles, and offers the previewed repair.
//

import SwiftLintRuleStudioCore
import SwiftUI

/// Shown above every section while the workspace's configuration has a rule-list problem.
///
/// SwiftLint gives no sign of the worst one in the app: the command-line edition discards
/// the warning it prints, falls back to its default configuration and lints everything,
/// `included` and `excluded` ignored (issue #83).
struct RuleListsProblemBanner: View {
    let problem: ConfigRuleListsProblem
    @State private var viewModel: RuleListsFixViewModel

    init(problem: ConfigRuleListsProblem, configPath: URL) {
        self.problem = problem
        self._viewModel = State(initialValue: RuleListsFixViewModel(configPath: configPath))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isConflict ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Review Fix…", action: viewModel.prepareFix)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("RuleListsProblemReviewFixButton")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RuleListsProblemBanner")
        .sheet(item: Bindable(viewModel).diff) { diff in
            // Opens on the full diff: the summary lists only per-rule settings, and this
            // repair rewrites the lists alone, so it would read "No changes".
            ConfigDiffPreviewView(
                diff: diff,
                ruleName: ".swiftlint.yml",
                onSave: viewModel.applyFix,
                onCancel: viewModel.cancel,
                selectedView: .full
            )
        }
        .alert("Couldn't Repair .swiftlint.yml", isPresented: TestGuard.alertBinding(errorShown)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var isConflict: Bool {
        problem == .onlyRulesConflict
    }

    private var tint: Color {
        isConflict ? .red : .orange
    }

    private var title: String {
        isConflict ? "SwiftLint ignores this .swiftlint.yml" : "Rules listed twice in .swiftlint.yml"
    }

    private var message: String {
        switch problem {
        case .onlyRulesConflict:
            return "It lists rules under only_rules and also under opt_in_rules or disabled_rules, "
                + "which SwiftLint doesn't allow. The swiftlint command falls back to its default "
                + "configuration, ignoring every setting here, included and excluded too. Rule changes "
                + "can't be saved until it's fixed. The fix moves those rules into only_rules, and the "
                + "rules shown as on are the ones it keeps."
        case .analyzerRulesInOnlyRules(let ruleIds):
            return "\(ruleIds.joined(separator: ", ")) \(ruleIds.count == 1 ? "is" : "are") listed "
                + "under both only_rules and analyzer_rules. Each runs once, but SwiftLint warns about "
                + "it on every run. The fix lists each of them once."
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
