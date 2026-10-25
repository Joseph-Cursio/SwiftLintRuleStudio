//
//  ImpactSimulationView.swift
//  SwiftLintRuleStudio
//
//  View for displaying impact simulation results
//

import SwiftLintRuleStudioCore
import SwiftUI

/// What a simulation result says about enabling the rule.
///
/// Safe and has-violations used to be the only two answers, so a result with no count — an
/// analyzer rule, which linting never runs — fell into whichever `isSafe` picked.
private enum ImpactVerdict {
    case safe
    case hasViolations
    case failed
    case unmeasurable

    init(_ result: RuleImpactResult) {
        switch result.measurement {
        case .measured: self = result.isSafe ? .safe : .hasViolations
        case .failed: self = .failed
        case .unmeasurable: self = .unmeasurable
        }
    }

    var iconName: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .hasViolations: "exclamationmark.triangle.fill"
        case .failed: "exclamationmark.octagon.fill"
        case .unmeasurable: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .hasViolations: .orange
        case .failed: .red
        case .unmeasurable: .secondary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .safe: "Safe rule"
        case .hasViolations: "Rule has violations"
        case .failed: "Simulation failed"
        case .unmeasurable: "Rule can't be measured"
        }
    }

    var headline: String {
        switch self {
        case .safe: "This rule is safe to enable"
        case .hasViolations: "This rule would introduce violations"
        case .failed: "The simulation failed"
        case .unmeasurable: "This rule's impact can't be measured here"
        }
    }
}

/// The verdict icon, the rule's name and id, and the one-line verdict.
///
/// Takes the three values it reads. `ImpactSimulationView` is also handed `onEnable`, a closure
/// the presenting screen allocates on every update, so the sheet value never compares equal and
/// its whole body re-runs — this does not.
private struct ImpactSimulationHeader: View {
    @ScaledMetric(relativeTo: .title) private var iconSizeMedium: CGFloat = 48

    let ruleId: String
    let ruleName: String
    let result: RuleImpactResult

    private var verdict: ImpactVerdict { ImpactVerdict(result) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: verdict.iconName)
                    .font(.system(size: iconSizeMedium))
                    .foregroundStyle(verdict.color)
                    .accessibilityLabel(verdict.accessibilityLabel)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ruleName)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(ruleId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(verdict.headline)
                .font(.headline)
                .foregroundStyle(verdict.color)

            if let explanation = result.measurement.explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ViolationRow: View {
    let violation: Violation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: violation.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(violation.severity == .error ? .red : .orange)
                .frame(width: 20)
                .accessibilityLabel(violation.severity == .error ? "Error" : "Warning")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(violation.filePath)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Line \(violation.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(violation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
    }
}

/// Violation count, affected files and simulation time.
///
/// Depends on the result alone. `ImpactSimulationView` also holds `ruleId`, `ruleName`,
/// `onEnable` and the dismiss action, none of which this draws.
private struct ImpactSummary: View {
    let result: RuleImpactResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Violations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // No count is shown as none, not as the -1 that stands in for one; the
                    // same goes for files and time below, where 0 would read as clean.
                    Text(result.isMeasured ? "\(result.violationCount)" : "—")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(ImpactVerdict(result).color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Affected Files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(result.isMeasured ? "\(result.affectedFiles.count)" : "—")
                        .font(.title)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulation Time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // Nothing ran for a rule with no count, so there is no time to show.
                    Text(result.isMeasured ? String(format: "%.2fs", result.simulationDuration) : "—")
                        .font(.title)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

/// The first twenty violations, with a note when there are more.
private struct ImpactViolations: View {
    let result: RuleImpactResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Violations")
                .font(.headline)

            if result.violations.isEmpty {
                Text("No violations found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(Array(result.violations.prefix(20)), id: \.id) { violation in
                    ViolationRow(violation: violation)
                }

                if result.violations.count > 20 {
                    Text("... and \(result.violations.count - 20) more violations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
    }
}

struct ImpactSimulationView: View {
    let ruleId: String
    let ruleName: String
    let result: RuleImpactResult
    let onEnable: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with result summary
                    ImpactSimulationHeader(ruleId: ruleId, ruleName: ruleName, result: result)

                    Divider()

                    // Violation count and affected files
                    ImpactSummary(result: result)

                    if result.hasViolations {
                        Divider()

                        // Violations list
                        ImpactViolations(result: result)
                    }
                }
                .padding()
            }
            .navigationTitle("Impact Simulation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if let onEnable = onEnable, Self.offersEnable(for: result) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enable Rule") {
                            onEnable()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
    }

    /// Whether the sheet offers "Enable Rule" for `result`: only for a measured, clean run.
    /// A failed or unmeasurable simulation has no count to call clean.
    ///
    /// A function rather than an inline condition so it can be tested: ViewInspector can't
    /// reach a toolbar item that sits inside an `if`.
    static func offersEnable(for result: RuleImpactResult) -> Bool {
        result.isSafe
    }
}

#Preview {
    let result = RuleImpactResult(
        ruleId: "force_cast",
        violationCount: 3,
        violations: [
            Violation(
                ruleID: "force_cast",
                filePath: "Test.swift",
                line: 10,
                severity: .error,
                message: "Force casts should be avoided",
                column: 5
            ),
            Violation(
                ruleID: "force_cast",
                filePath: "Another.swift",
                line: 25,
                severity: .warning,
                message: "Force casts should be avoided",
                column: 12
            )
        ],
        affectedFiles: ["Test.swift", "Another.swift"],
        simulationDuration: 1.23
    )

    return ImpactSimulationView(
        ruleId: "force_cast",
        ruleName: "Force Cast",
        result: result,
        onEnable: nil
    )
}
