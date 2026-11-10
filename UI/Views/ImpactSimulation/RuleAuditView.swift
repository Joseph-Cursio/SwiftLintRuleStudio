//
//  RuleAuditView.swift
//  SwiftLintRuleStudio
//
//  View for auditing all rules against the workspace
//

import SwiftLintRuleStudioCore
import SwiftUI

struct RuleAuditView: View {
    @State private var model: RuleAuditModel

    init() {
        _model = State(initialValue: RuleAuditModel())
    }

    init(
        auditEntries: [RuleAuditEntry],
        selectedRules: Set<String> = [],
        totalSwiftFiles: Int = 0,
        auditDuration: TimeInterval = 0
    ) {
        _model = State(initialValue: RuleAuditModel(
            auditEntries: auditEntries,
            selectedRules: selectedRules,
            totalSwiftFiles: totalSwiftFiles,
            auditDuration: auditDuration
        ))
    }

    var body: some View {
        RuleAuditContent(model: model)
    }
}

#Preview {
    RuleAuditView()
        .environment(\.dependencies, DependencyContainer(
            swiftLintCLI: UnconfiguredSwiftLintBackend()
        ))
}
