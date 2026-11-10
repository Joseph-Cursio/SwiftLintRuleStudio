//
//  SwiftLintRuleStudioUITests.swift
//  SwiftLintRuleStudioUITests
//
//  Created by joe cursio on 12/24/25.
//

import XCTest

@MainActor
final class SwiftLintRuleStudioUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { Self.terminateApp() }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { Self.terminateApp() }
    }

    @MainActor private static func terminateApp() {
        let app = XCUIApplication()
        guard app.state != .notRunning else { return }
        app.terminate()
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testOnboardingFlow() throws {
        let app = launchApp()
        let window = waitForMainWindow(in: app)
        if !window.exists {
            XCTFail("No window available for UI flow assertions. \(app.debugDescription)")
            return
        }

        let welcomeTitle = findElement(in: window, identifier: "OnboardingWelcomeTitle")
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 5))

        let nextButton = findElement(in: window, identifier: "OnboardingNextButton")
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        let enabledPredicate = NSPredicate(format: "enabled == true")
        let nextEnabledExpectation = XCTNSPredicateExpectation(
            predicate: enabledPredicate, object: nextButton
        )
        _ = XCTWaiter.wait(for: [nextEnabledExpectation], timeout: 5.0)
        nextButton.click()

        let nextButtonAfterCheck = findElement(in: window, identifier: "OnboardingNextButton")
        let nextCheckEnabledExpectation = XCTNSPredicateExpectation(
            predicate: enabledPredicate,
            object: nextButtonAfterCheck
        )
        _ = XCTWaiter.wait(for: [nextCheckEnabledExpectation], timeout: 5.0)
        nextButtonAfterCheck.click()

        let workspaceTitle = window.staticTexts["Select a Workspace"]
        XCTAssertTrue(workspaceTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainNavigation() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No window available"); return
        }

        // Each leg asserts the destination arrived *and* that the previous one
        // left. Before this, the test clicked three links and asserted nothing
        // about the result, so it passed just as happily when the clicks did
        // nothing at all -- which, on the macOS 27 SDK, they did.
        findElement(in: window, identifier: "SidebarRulesLink").click()
        assertShowing(
            window,
            present: Marker.rules,
            absent: Marker.violations + Marker.audit,
            "Rules"
        )

        findElement(in: window, identifier: "SidebarViolationsLink").click()
        assertShowing(
            window,
            present: Marker.violations,
            absent: Marker.rules + Marker.audit,
            "Violations"
        )

        findElement(in: window, identifier: "SidebarRuleAuditLink").click()
        assertShowing(
            window,
            present: Marker.audit,
            absent: Marker.rules + Marker.violations,
            "Rule Audit"
        )
    }
}
