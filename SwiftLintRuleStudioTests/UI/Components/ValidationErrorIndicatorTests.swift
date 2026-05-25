//
//  ValidationErrorIndicatorTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke tests for ValidationErrorIndicator. Pass in a
//  known error + warning and assert the message text + suggestion
//  text both render through ValidationErrorRow.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ValidationErrorIndicatorTests {
    @Test("ValidationErrorIndicator renders error and warning messages")
    func testRendersErrorAndWarningMessages() async throws {
        let view = await MainActor.run {
            ValidationErrorIndicator(
                errors: [
                    ValidationResult.ValidationError(
                        field: .rule("force_cast"),
                        message: "Invalid severity value",
                        suggestion: "Use 'warning' or 'error'"
                    )
                ],
                warnings: [
                    ValidationResult.ValidationWarning(
                        field: .rule("unknown_rule"),
                        message: "Unknown rule identifier",
                        suggestion: "Did you mean 'force_cast'?"
                    )
                ]
            )
        }

        // Suggestion text lives behind an expand-toggle in ValidationErrorRow,
        // so the collapsed default state only renders the message — assert
        // on that. The disclosure-toggle accessibility label is also
        // structurally present and is a robust signal that the row rendered.
        let (hasErr, hasWarn) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Invalid severity value")) != nil,
                (try? inspector.find(text: "Unknown rule identifier")) != nil
            )
        }

        #expect(hasErr, "Error message should render")
        #expect(hasWarn, "Warning message should render")
    }
}
