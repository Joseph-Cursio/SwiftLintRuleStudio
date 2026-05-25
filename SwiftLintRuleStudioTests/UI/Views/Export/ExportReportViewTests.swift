//
//  ExportReportViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for ExportReportView. The view reads
//  dependencies via @Environment and shows its format/options sections
//  at launch regardless of violation state; we mount it with a test
//  container and assert the section headers render.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Foundation
import SwiftUI
import Testing
import ViewInspector

// Workaround type to bypass the Sendable check on `some View` when bouncing
// the hosted view across MainActor.run boundaries — same pattern other UI
// tests in this target use.
@MainActor
private struct ViewResult: @unchecked Sendable {
    let view: AnyView
}

@MainActor
struct ExportReportViewTests {
    @Test("ExportReportView renders Export Format / Include in Report / Output section headers")
    func testRendersSectionHeaders() async throws {
        let result: ViewResult = await MainActor.run {
            let container = DependencyContainer.createForTesting()
            let view = ExportReportView().environment(\.dependencies, container)
            return ViewResult(view: AnyView(view))
        }

        let (hasFormat, hasInclude, hasOutput) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (
                (try? inspector.find(text: "Export Format")) != nil,
                (try? inspector.find(text: "Include in Report")) != nil,
                (try? inspector.find(text: "Output")) != nil
            )
        }

        #expect(hasFormat)
        #expect(hasInclude)
        #expect(hasOutput)
    }
}
