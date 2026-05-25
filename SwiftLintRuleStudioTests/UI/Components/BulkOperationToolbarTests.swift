//
//  BulkOperationToolbarTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for BulkOperationToolbar. The view takes
//  closure handlers; we pass no-op closures and assert the visible
//  labels render for the selection-count + Set Severity / Clear menus.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct BulkOperationToolbarTests {
    @Test("BulkOperationToolbar renders selection count and trailing controls")
    func testRendersSelectionCountAndControls() async throws {
        let view = await MainActor.run {
            BulkOperationToolbar(
                selectedCount: 3,
                onEnableAll: {},
                onDisableAll: {},
                onSetSeverity: { _ in },
                onPreview: {},
                onClearSelection: {}
            )
        }

        let (hasCount, hasSeverityMenu, hasClear) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "3 selected")) != nil,
                (try? inspector.find(text: "Set Severity")) != nil,
                (try? inspector.find(text: "Clear")) != nil
            )
        }

        #expect(hasCount, "Selection-count label should reflect the constructor argument")
        #expect(hasSeverityMenu)
        #expect(hasClear)
    }
}
