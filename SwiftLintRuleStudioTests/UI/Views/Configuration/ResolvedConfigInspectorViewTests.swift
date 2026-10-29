//
//  ResolvedConfigInspectorViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector tests for ResolvedConfigInspectorView — the resolved-config
//  detail pane (layer chain, attributed rule rows, notices).
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ResolvedConfigInspectorViewTests {
    private func texts(_ view: some View) throws -> [String] {
        ViewHosting.expel()
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }
        return try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
    }

    @Test("renders the layer chain, attributed rule rows, and excluded notice")
    func testRendersResolvedContent() throws {
        let display = ResolvedConfigDisplay(
            targetLabel: "Tests",
            layerChainLabels: ["root", "Tests"],
            ruleRows: [
                ResolvedRuleRow(id: "force_unwrapping", state: "off (disabled)", setBy: "Tests", detail: nil),
                ResolvedRuleRow(id: "line_length", state: "configured", setBy: "Legacy", detail: "overrides root")
            ],
            onlyRulesNotice: nil,
            excludedNotice: "excluded (root): Generated",
            inheritsNotice: nil,
            skippedNotice: nil
        )

        let rendered = try texts(ResolvedConfigInspectorView(display: display))

        #expect(rendered.contains("Tests"))
        #expect(rendered.contains("Layer chain: root ▸ Tests"))
        #expect(rendered.contains("force_unwrapping"))
        #expect(rendered.contains("off (disabled)"))
        #expect(rendered.contains("overrides root"))
        #expect(rendered.contains("excluded (root): Generated"))
        // Column headers confirm the rule table rendered.
        #expect(rendered.contains("Set by"))
    }

    @Test("renders the inherits notice and empty-rules copy")
    func testInheritsAndNoChanges() throws {
        let display = ResolvedConfigDisplay(
            targetLabel: "Sources/Feature",
            layerChainLabels: ["root"],
            ruleRows: [],
            onlyRulesNotice: nil,
            excludedNotice: nil,
            inheritsNotice: "No config in this folder — it inherits from root.",
            skippedNotice: nil
        )

        let rendered = try texts(ResolvedConfigInspectorView(display: display))

        #expect(rendered.contains("No config in this folder — it inherits from root."))
        #expect(rendered.contains("No rule changes from the SwiftLint defaults in this folder."))
    }

    @Test("renders the notice naming the nested configs that don't apply")
    func testSkippedNotice() throws {
        let notice = "Sub's config doesn't apply here — SwiftLint applies only the root config and "
            + "the nearest nested config, Deeper."
        let display = ResolvedConfigDisplay(
            targetLabel: "Sub/Deeper",
            layerChainLabels: ["root", "Deeper"],
            ruleRows: [],
            onlyRulesNotice: nil,
            excludedNotice: nil,
            inheritsNotice: nil,
            skippedNotice: notice
        )

        let rendered = try texts(ResolvedConfigInspectorView(display: display))

        #expect(rendered.contains("Layer chain: root ▸ Deeper"))
        #expect(rendered.contains(notice))
    }
}
