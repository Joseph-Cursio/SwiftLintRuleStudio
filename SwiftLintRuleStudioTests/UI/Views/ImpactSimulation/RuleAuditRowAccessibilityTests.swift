//
//  RuleAuditRowAccessibilityTests.swift
//  SwiftLintRuleStudioTests
//
//  Accessibility regression for P2.4: the audit row put `.isButton` on an
//  uncombined ~9-column HStack, so VoiceOver read ~9 separate stops per row. The
//  row must now be one element carrying a composed summary label.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleAuditRowAccessibilityTests {
    private func makeRow() -> RuleAuditRow {
        let rule = Rule(
            id: "force_cast", name: "Force Cast", description: "Avoid force casting",
            category: .lint, isOptIn: false, severity: .warning, parameters: nil,
            triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
            isEnabled: false, supportsAutocorrection: false
        )
        let impact = RuleImpactResult(
            ruleId: "force_cast", violationCount: 5, violations: [],
            affectedFiles: ["A.swift"], simulationDuration: 0.1
        )
        let entry = RuleAuditEntry(rule: rule, impactResult: impact, isCurrentlyEnabled: false)
        return RuleAuditRow(
            entry: entry, isExpanded: false, isSelected: false,
            totalSwiftFiles: 10, maxViolationCount: 10,
            onToggleExpand: {}, onToggleSelect: {}, onEnable: {}
        )
    }

    @Test("The audit row exposes a single composed accessibility label")
    func rowHasComposedLabel() throws {
        let row = makeRow()
        let matchesComposedLabel: (InspectableView<ViewType.ClassifiedView>) throws -> Bool = { view in
            guard let label = try? view.accessibilityLabel().string() else { return false }
            return label.contains("force_cast") && label.contains("5 violations")
        }
        let hasComposedLabel = (try? row.inspect().find(where: matchesComposedLabel)) != nil
        #expect(hasComposedLabel, "the row must carry a composed label with rule id + violation count")
    }
}
