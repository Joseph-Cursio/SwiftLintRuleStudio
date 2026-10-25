//
//  RuleDetailViewSimulationTests.swift
//  SwiftLintRuleStudioTests
//
//  A single-rule simulation that throws must reach the Impact Simulation sheet as a failure
//  with its reason. It used to raise the save-error alert instead, which blamed a save that
//  never happened.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleDetailViewSimulationTests {
    private struct MirrorFailure: LocalizedError {
        var errorDescription: String? { "Couldn't build the mirror" }
    }

    @Test("A simulation that throws becomes a failure carrying why")
    func throwingSimulationBecomesFailure() async {
        let result = await RuleDetailView.simulationResult(ruleId: "force_cast") {
            throw MirrorFailure()
        }

        #expect(result.ruleId == "force_cast")
        #expect(result.measurement == .failed(reason: "Couldn't build the mirror"))
        #expect(result.isSafe == false)
    }

    @Test("A simulation that succeeds comes back as it was")
    func succeedingSimulationPassesThrough() async {
        let result = await RuleDetailView.simulationResult(ruleId: "force_cast") {
            RuleImpactResult(
                ruleId: "force_cast",
                violationCount: 2,
                violations: [],
                affectedFiles: ["A.swift"],
                simulationDuration: 0.5
            )
        }

        #expect(result.measurement == .measured)
        #expect(result.violationCount == 2)
    }

    @Test("The sheet shows a failed simulation as failed, with the reason, and offers no Enable")
    func sheetShowsTheFailure() throws {
        let failedResult = RuleImpactResult.failed(ruleId: "force_cast", reason: "Couldn't build the mirror")
        let failed = try Self.inspectSheet(for: failedResult)
        // The control: a clean measured run reads as safe and is offered Enable, so the
        // failed run's "no" is the measurement's doing.
        let safeResult = RuleImpactResult(
            ruleId: "force_cast",
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
        let safe = try Self.inspectSheet(for: safeResult)

        #expect(failed.texts.contains("The simulation failed"))
        #expect(failed.texts.contains("Couldn't build the mirror"))
        #expect(!failed.texts.contains("This rule is safe to enable"))
        #expect(safe.texts.contains("This rule is safe to enable"))
        // The toolbar's Enable button is gated on this; ViewInspector can't reach the button
        // itself, which sits inside an `if` in the toolbar.
        #expect(ImpactSimulationView.offersEnable(for: safeResult), "a safe result offers Enable")
        #expect(!ImpactSimulationView.offersEnable(for: failedResult), "a failed result doesn't")
        #expect(!ImpactSimulationView.offersEnable(
            for: .unmeasurable(ruleId: "force_cast", reason: .analyzerRule)
        ), "nor does one lint can't measure")
    }

    // MARK: - Options

    private static func makeRule(usesSourceKit: Bool) -> Rule {
        Rule(
            id: "sk_rule",
            name: "SourceKit Rule",
            description: "desc",
            category: .lint,
            isOptIn: true,
            usesSourceKit: usesSourceKit
        )
    }

    @Test("In the sandboxed edition a SourceKit rule is simulated as one SwiftLint can't lint here")
    func sourceKitRuleIsUnlintableWithoutSourceKit() {
        let options = RuleDetailView.simulationOptions(
            for: Self.makeRule(usesSourceKit: true),
            capabilities: [],
            parameterValues: [:]
        )

        #expect(options.isSourceKitUnavailable, "else it would come back a \"safe\" 0")
        #expect(options.isOptIn)
        #expect(options.parameterOverrides == nil)
    }

    @Test("With SourceKit, a SourceKit rule is simulated, with the editor's unsaved parameters")
    func sourceKitRuleIsLintedWithSourceKit() {
        let options = RuleDetailView.simulationOptions(
            for: Self.makeRule(usesSourceKit: true),
            capabilities: Set(AppCapability.allCases),
            parameterValues: ["warning": AnyCodable(80)]
        )

        #expect(!options.isSourceKitUnavailable)
        #expect(options.parameterOverrides?["warning"] == AnyCodable(80))
    }

    // MARK: - Helpers

    private struct InspectedSheet {
        let texts: Set<String>
    }

    /// The sheet for `result`, given an enable action, as the rule detail presents it.
    private static func inspectSheet(for result: RuleImpactResult) throws -> InspectedSheet {
        let view = ImpactSimulationView(ruleId: "force_cast", ruleName: "Force Cast", result: result) {}

        ViewHosting.expel()
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }
        let inspector = try view.inspect()

        let texts = ["The simulation failed", "Couldn't build the mirror", "This rule is safe to enable"]
            .filter { (try? inspector.find(text: $0)) != nil }
        return InspectedSheet(texts: Set(texts))
    }
}
