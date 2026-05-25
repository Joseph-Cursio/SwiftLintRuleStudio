//
//  TemplateLibraryViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for TemplateLibraryView. Promoted from
//  file-private so the test target can reach it via @testable import.
//  The default ConfigurationTemplateManager loads the built-in catalog
//  and the view renders its navigation title and project filter.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct TemplateLibraryViewTests {
    @Test("TemplateLibraryView renders the 'All Projects' filter and an empty-detail placeholder")
    func testRendersFilterAndEmptyPlaceholder() async throws {
        let view = await MainActor.run {
            TemplateLibraryView()
        }

        let (hasAllProjects, hasEmptyDetail) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "All Projects")) != nil,
                (try? inspector.find(text: "Choose a template to see its details")) != nil
            )
        }

        #expect(hasAllProjects, "Project-type filter label should render")
        #expect(hasEmptyDetail, "Empty detail placeholder should render when no template is selected")
    }
}
