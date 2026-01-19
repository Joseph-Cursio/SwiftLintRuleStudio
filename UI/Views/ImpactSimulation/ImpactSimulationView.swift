//
//  ImpactSimulationView.swift
//  SwiftLintRuleStudio
//
//  View for displaying impact simulation results
//

import SwiftUI

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
                    headerView
                    
                    Divider()
                    
                    // Violation count and affected files
                    summaryView
                    
                    if result.hasViolations {
                        Divider()
                        
                        // Violations list
                        violationsView
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
                
                if let onEnable = onEnable, result.isSafe {
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
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isSafe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(result.isSafe ? .green : .orange)
                    .accessibilityLabel(result.isSafe ? "Safe rule" : "Rule has violations")
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(ruleName)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(ruleId)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text(result.isSafe ? "This rule is safe to enable" : "This rule would introduce violations")
                .font(.headline)
                .foregroundColor(result.isSafe ? .green : .orange)
        }
    }
    
    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Violations")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(result.violationCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(result.isSafe ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Affected Files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(result.affectedFiles.count)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulation Time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2fs", result.simulationDuration))
                        .font(.title)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var violationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Violations")
                .font(.headline)
            
            if result.violations.isEmpty {
                Text("No violations found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(result.violations.prefix(20)), id: \.id) { violation in
                    ViolationRow(violation: violation)
                }
                
                if result.violations.count > 20 {
                    Text("... and \(result.violations.count - 20) more violations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
    }
}

struct ViolationRow: View {
    let violation: Violation
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: violation.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(violation.severity == .error ? .red : .orange)
                .frame(width: 20)
                .accessibilityLabel(violation.severity == .error ? "Error" : "Warning")
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(violation.filePath)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Line \(violation.line)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(violation.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
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
                column: 5,
                severity: .error,
                message: "Force casts should be avoided"
            ),
            Violation(
                ruleID: "force_cast",
                filePath: "Another.swift",
                line: 25,
                column: 12,
                severity: .warning,
                message: "Force casts should be avoided"
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

