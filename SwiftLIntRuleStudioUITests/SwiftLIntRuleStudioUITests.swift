//
//  SwiftLIntRuleStudioUITests.swift
//  SwiftLIntRuleStudioUITests
//
//  Created by joe cursio on 12/24/25.
//

import XCTest

final class SwiftLIntRuleStudioUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        let app = XCUIApplication()
        terminateIfRunning(app)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        terminateIfRunning(XCUIApplication())
    }

    private func terminateIfRunning(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
    }

    private func launchApp(
        skipOnboarding: Bool = false,
        createWorkspace: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        if skipOnboarding {
            app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        }
        if createWorkspace {
            app.launchEnvironment["UI_TEST_WORKSPACE"] = "1"
        }
        app.launch()
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    private func waitForMainWindow(
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "count > 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)

        let window = app.windows.element(boundBy: 0)
        if !window.exists {
            app.activate()
            _ = window.waitForExistence(timeout: 2)
        }
        return window
    }

    private func findElement(
        in root: XCUIElement,
        identifier: String
    ) -> XCUIElement {
        let candidates: [XCUIElement] = [
            root.buttons[identifier],
            root.staticTexts[identifier],
            root.otherElements[identifier],
            root.cells[identifier],
            root.outlines[identifier],
            root.outlines.cells[identifier]
        ]
        if let match = candidates.first(where: { $0.exists }) {
            return match
        }
        return root.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
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
        let nextEnabledExpectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: nextButton)
        _ = XCTWaiter.wait(for: [nextEnabledExpectation], timeout: 5.0)
        nextButton.tap()

        let nextButtonAfterCheck = findElement(in: window, identifier: "OnboardingNextButton")
        let nextCheckEnabledExpectation = XCTNSPredicateExpectation(
            predicate: enabledPredicate,
            object: nextButtonAfterCheck
        )
        _ = XCTWaiter.wait(for: [nextCheckEnabledExpectation], timeout: 5.0)
        nextButtonAfterCheck.tap()

        let workspaceTitle = window.staticTexts["Select a Workspace"]
        XCTAssertTrue(workspaceTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainNavigation() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        if !window.exists {
            XCTFail("No window available for UI navigation assertions. \(app.debugDescription)")
            return
        }

        let rulesRow = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesRow.waitForExistence(timeout: 5))
        rulesRow.tap()

        let violationsRow = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsRow.waitForExistence(timeout: 5))
        violationsRow.tap()

        let safeRulesRow = findElement(in: window, identifier: "SidebarSafeRulesLink")
        XCTAssertTrue(safeRulesRow.waitForExistence(timeout: 5))
        safeRulesRow.tap()
    }
}
