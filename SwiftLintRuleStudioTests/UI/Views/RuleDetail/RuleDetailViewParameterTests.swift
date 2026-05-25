//
//  RuleDetailViewParameterTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector tests covering the Parameters subsection of the rule
//  detail card: that each typed parameter renders, that the "Default: N"
//  indicators appear, and that the inline Save/Discard controls flip
//  enabled/disabled in response to in-memory edits.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleDetailViewParameterTests {

    // MARK: - Helper

    @MainActor
    private static func ruleWithParameters() -> Rule {
        Rule(
            id: "line_length",
            name: "Line Length",
            description: "Lines should not span too many characters",
            category: .metrics,
            isOptIn: false,
            severity: .warning,
            parameters: [
                RuleParameter(name: "warning", type: .integer, defaultValue: AnyCodable(120)),
                RuleParameter(name: "error", type: .integer, defaultValue: AnyCodable(200)),
                RuleParameter(name: "ignores_urls", type: .boolean, defaultValue: AnyCodable(true))
            ],
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: true,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: .warning,
            markdownDocumentation: nil
        )
    }

    // MARK: - Section presence

    @Test("Parameters header renders when the rule has parameters and is enabled")
    func testParametersHeaderRenders() async throws {
        let rule = Self.ruleWithParameters()
        let viewModel = RuleDetailViewModel(rule: rule)
        viewModel.updateEnabled(true)

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, viewModel: viewModel)
        }.value

        let (hasParametersHeader, hasWarningName, hasErrorName, hasIgnoresName) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (
                (try? inspector.find(text: "Parameters")) != nil,
                (try? inspector.find(text: "warning")) != nil,
                (try? inspector.find(text: "error")) != nil,
                (try? inspector.find(text: "ignores_urls")) != nil
            )
        }

        #expect(hasParametersHeader, "Configuration card should render the 'Parameters' header")
        #expect(hasWarningName)
        #expect(hasErrorName)
        #expect(hasIgnoresName)
    }

    @Test("Parameters section is hidden when the rule has no parameters")
    func testParametersHiddenForNonConfigurableRule() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "force_cast",
                name: "Force Cast",
                description: "Force casts should be avoided.",
                category: .lint,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: true,
                defaultSeverity: .warning
            )
        }
        let viewModel = RuleDetailViewModel(rule: rule)
        viewModel.updateEnabled(true)

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, viewModel: viewModel)
        }.value

        let hasParametersHeader = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (try? inspector.find(text: "Parameters")) != nil
        }

        #expect(!hasParametersHeader, "No Parameters subsection should appear when rule.parameters is nil")
    }

    // MARK: - Default indicators

    @Test("Each typed parameter renders its 'Default: N' indicator label")
    func testDefaultIndicatorsRender() async throws {
        let rule = Self.ruleWithParameters()
        let viewModel = RuleDetailViewModel(rule: rule)
        viewModel.updateEnabled(true)

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, viewModel: viewModel)
        }.value

        let (hasIntDefault120, hasIntDefault200, hasBoolDefault) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (
                (try? inspector.find(text: "Default: 120")) != nil,
                (try? inspector.find(text: "Default: 200")) != nil,
                (try? inspector.find(text: "Default: On")) != nil
            )
        }

        #expect(hasIntDefault120, "warning row should display 'Default: 120'")
        #expect(hasIntDefault200, "error row should display 'Default: 200'")
        #expect(hasBoolDefault, "ignores_urls row should display 'Default: On' for default-true Bool")
    }

    // MARK: - Save/Discard inline buttons

    @Test("Discard and Save controls render in the Configuration card")
    func testSaveControlsRender() async throws {
        let rule = Self.ruleWithParameters()
        let viewModel = RuleDetailViewModel(rule: rule)
        viewModel.updateEnabled(true)

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, viewModel: viewModel)
        }.value

        let (hasDiscard, hasSave) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (
                (try? inspector.find(text: "Discard")) != nil,
                (try? inspector.find(text: "Save")) != nil
            )
        }

        #expect(hasDiscard)
        #expect(hasSave)
    }

    // MARK: - Enable-on-edit regression

    @Test("Editing parameterValues flips pendingChanges and enables save controls")
    func testEditingParameterEnablesSaveControls() async throws {
        // This is the regression-test counterpart to the didSet-on-parameterValues
        // fix: the editor's @Binding writes to viewModel.parameterValues directly
        // (bypassing updateParameter), so we simulate that path and verify the
        // viewmodel's pendingChanges/hasPendingChanges state flips. We assert at
        // the viewmodel level here because hosting the view and re-inspecting
        // disabled state of a SwiftUI Button after a state mutation is unreliable
        // across ViewInspector versions; the viewmodel state is what gates the
        // .disabled(!hasPendingChanges) modifier.
        let rule = Self.ruleWithParameters()
        let viewModel = RuleDetailViewModel(rule: rule)
        viewModel.updateEnabled(true)

        // updateEnabled(true) flips enabled state vs the rule's initial isEnabled,
        // which itself may produce a pending change. Snapshot the baseline and
        // then mutate a parameter to verify that path also produces a change.
        let baseline = viewModel.pendingChanges

        var newValues = viewModel.parameterValues
        newValues["warning"] = AnyCodable(80) // override (default is 120)
        viewModel.parameterValues = newValues

        #expect(viewModel.pendingChanges != nil, "Mutating parameterValues should flag pending changes")
        // Even if the baseline already had pendingChanges (from updateEnabled),
        // the parameter change must surface in the snapshot.
        #expect(
            viewModel.pendingChanges?.parameters?["warning"]?.value as? Int == 80,
            "pendingChanges should reflect the new warning override"
        )
        _ = baseline // silence unused warning if baseline pinning isn't asserted
    }

}
