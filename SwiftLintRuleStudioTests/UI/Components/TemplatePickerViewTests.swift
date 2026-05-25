//
//  TemplatePickerViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for TemplatePickerView. The view is just
//  promoted from `private` to module-internal so the test target can
//  reach it via @testable import; the default template manager loads
//  the built-in catalog and the view renders its header / count.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct TemplatePickerViewTests {
    @Test("TemplatePickerView renders the picker header title")
    func testRendersHeader() async throws {
        // The Select call-to-action lives behind a hover state we can't
        // reliably drive in ViewInspector, so this test sticks to the always-
        // visible header.
        let view = await MainActor.run {
            TemplatePickerView { _ in }
        }

        let hasTitle = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (try? inspector.find(text: "Choose a Template")) != nil
        }

        #expect(hasTitle, "Header title should render")
    }
}
