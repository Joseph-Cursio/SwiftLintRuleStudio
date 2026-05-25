//
//  ConfigComparisonViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke tests for ConfigComparisonView. The service stub
//  returns the empty result the view shows before the user has selected
//  any configs to compare; we assert that the initial header labels
//  ("Left Config" / "Right Config") render.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

private struct StubConfigComparisonService: ConfigComparisonServiceProtocol {
    func compare(
        config1 _: URL,
        label1 _: String,
        config2 _: URL,
        label2 _: String
    ) throws -> ConfigComparisonResult {
        // Tests don't trigger a comparison; the empty result satisfies the
        // protocol if a future test wires the file pickers.
        ConfigComparisonResult(
            onlyInFirst: [],
            onlyInSecond: [],
            inBothDifferent: [],
            inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [],
                before: "", after: ""
            )
        )
    }
}

@MainActor
struct ConfigComparisonViewTests {
    @Test("ConfigComparisonView renders left/right config slot headers in its initial empty state")
    func testInitialEmptyStateRendersSlotHeaders() async throws {
        let view = await MainActor.run {
            ConfigComparisonView(service: StubConfigComparisonService(), currentWorkspace: nil)
        }

        let (hasLeft, hasRight, hasEmpty) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Left Config")) != nil,
                (try? inspector.find(text: "Right Config")) != nil,
                (try? inspector.find(text: "No config selected")) != nil
            )
        }

        #expect(hasLeft, "Left slot header should render")
        #expect(hasRight, "Right slot header should render")
        #expect(hasEmpty, "Empty-state placeholder should render")
    }
}
