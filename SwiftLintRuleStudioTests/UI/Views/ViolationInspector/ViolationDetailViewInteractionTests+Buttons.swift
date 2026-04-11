//
//  ViolationDetailViewInteractionTests+Buttons.swift
//  SwiftLintRuleStudioTests
//
//  Open in Xcode and button visibility tests for ViolationDetailView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// MARK: - Open in Xcode Button Tests

extension ViolationDetailViewInteractionTests {

    @Test("ViolationDetailView open in Xcode button exists")
    func testOpenInXcodeButtonExists() async throws {
        let violation = makeTestViolation()
        let result = await Task { @MainActor in
            createViolationDetailView(violation: violation)
        }.value

        let hasOpenButton = try await MainActor.run {
            let buttons = try result.view.inspect().findAll(ViewType.Button.self)
            let openButton = buttons.first { button in
                do {
                    _ = try button.find(text: "Open in Xcode")
                    return true
                } catch {
                    return false
                }
            }
            return openButton != nil
        }
        #expect(hasOpenButton == true, "ViolationDetailView should have 'Open in Xcode' button")
    }

    @Test("ViolationDetailView open in Xcode button is tappable")
    func testOpenInXcodeButtonIsTappable() async throws {
        let violation = makeTestViolation()
        let result = await Task { @MainActor in
            createViolationDetailView(violation: violation)
        }.value

        let isTappable = try await MainActor.run {
            let buttons = try result.view.inspect().findAll(ViewType.Button.self)
            let openButton = buttons.first { button in
                do {
                    _ = try button.find(text: "Open in Xcode")
                    return true
                } catch {
                    return false
                }
            }

            guard let openButton = openButton else {
                return false
            }

            try openButton.tap()
            return true
        }
        #expect(isTappable == true, "Open in Xcode button should be tappable")
    }

    // MARK: - Button Visibility Tests

    @Test("ViolationDetailView suppress button is hidden when suppressed")
    func testSuppressButtonHiddenWhenSuppressed() async throws {
        let violation = makeTestViolation(suppressed: true)
        let result = await Task { @MainActor in
            createViolationDetailView(violation: violation)
        }.value

        let hasSuppressButton = await MainActor.run {
            let suppressText = try? result.view.inspect().find(text: "Suppress")
            return suppressText != nil
        }
        #expect(
            hasSuppressButton == false,
            "Suppress button should be hidden when violation is suppressed"
        )
    }

    @Test("ViolationDetailView resolve button is hidden when resolved")
    func testResolveButtonHiddenWhenResolved() async throws {
        let violation = makeTestViolation(resolvedAt: Date.now)
        let result = await Task { @MainActor in
            createViolationDetailView(violation: violation)
        }.value

        let hasResolveButton = await MainActor.run {
            (try? findButton(in: result.view, label: "Mark as Resolved")) != nil
        }
        #expect(
            hasResolveButton == false,
            "Resolve button should be hidden when violation is resolved"
        )
    }
}
