//
//  CustomRuleConflictBannerTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector test for CustomRuleConflictBanner.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct CustomRuleConflictBannerTests {
    @Test("renders the advisory message for each conflict")
    func testRendersAdvisory() throws {
        let view = CustomRuleConflictBanner(
            conflicts: [CustomRuleConflict(ruleIdentifier: "leading_whitespace")]
        )

        ViewHosting.expel()
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }

        let texts = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }

        let advisory = try #require(texts.first { $0.contains("leading_whitespace") })
        #expect(advisory.contains("built-in"))
        #expect(advisory.contains("consider renaming"))
    }
}
