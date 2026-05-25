//
//  ContentViewSectionsTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector tests for the sectionDetailView routing in
//  ContentView+Sections.swift. Each case in the AppSection switch needs
//  to be exercised at least once; we host ContentView with the test
//  dependency container, mutate its `selection` @State property, and
//  assert one signature label per branch renders.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

@MainActor
private struct ViewResult: @unchecked Sendable {
    let view: AnyView
}

@MainActor
struct ContentViewSectionsTests {

    private func makeView(selection: AppSection?) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let content = ContentView(initialSelection: selection)
        let wrapped = content.sectionDetailView
            .environment(\.dependencies, container)
            .environment(\.ruleRegistry, container.ruleRegistry)
        return ViewResult(view: AnyView(wrapped))
    }

    private func assertContainsText(
        _ text: String,
        in result: ViewResult,
        file _: String = #file,
        line _: Int = #line
    ) async throws -> Bool {
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (try? inspector.find(text: text)) != nil
        }
    }

    @Test(".none case renders the 'Select a section' placeholder")
    func testNoneCase() async throws {
        let result = await MainActor.run { makeView(selection: nil) }
        #expect(try await assertContainsText("Select a section", in: result))
    }

    @Test(".dashboard case renders the Dashboard placeholder")
    func testDashboardCase() async throws {
        let result = await MainActor.run { makeView(selection: .dashboard) }
        #expect(try await assertContainsText("Dashboard", in: result))
    }

    @Test(".exportReport case routes to ExportReportView")
    func testExportReportCase() async throws {
        let result = await MainActor.run { makeView(selection: .exportReport) }
        #expect(try await assertContainsText("Export Format", in: result))
    }

    @Test(".versionHistory case routes to ConfigVersionHistoryView")
    func testVersionHistoryCase() async throws {
        let result = await MainActor.run { makeView(selection: .versionHistory) }
        #expect(
            try await assertContainsText(
                "Configuration backups will appear here after you save changes.",
                in: result
            )
        )
    }

    @Test(".compareConfigs case routes to ConfigComparisonView")
    func testCompareConfigsCase() async throws {
        let result = await MainActor.run { makeView(selection: .compareConfigs) }
        #expect(try await assertContainsText("Left Config", in: result))
    }

    @Test(".versionCheck case routes to VersionCompatibilityView")
    func testVersionCheckCase() async throws {
        let result = await MainActor.run { makeView(selection: .versionCheck) }
        #expect(try await assertContainsText("SwiftLint Version", in: result))
    }

    @Test(".importConfig case routes to ConfigImportView")
    func testImportConfigCase() async throws {
        let result = await MainActor.run { makeView(selection: .importConfig) }
        #expect(try await assertContainsText("Import from URL", in: result))
    }

    @Test(".branchDiff case routes to GitBranchDiffView")
    func testBranchDiffCase() async throws {
        let result = await MainActor.run { makeView(selection: .branchDiff) }
        #expect(try await assertContainsText("Not a Git Repository", in: result))
    }

    @Test(".migration case routes to MigrationAssistantView")
    func testMigrationCase() async throws {
        let result = await MainActor.run { makeView(selection: .migration) }
        #expect(try await assertContainsText("Version Migration", in: result))
    }
}
