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
        MainActor.assumeIsolated { SwiftLintRuleStudioUITests.terminateApp() }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { SwiftLintRuleStudioUITests.terminateApp() }
    }

    @MainActor private static func terminateApp() {
        let app = XCUIApplication()
        guard app.state != .notRunning else { return }
        app.terminate()
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
    }

    // swiftlint:disable test_case_accessibility
    // Helpers are internal so the extension file can access them.
    func terminateIfRunning(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
    }

    func launchApp(
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

    func waitForMainWindow(
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

    /// Launches app with workspace, waits for main window, and ensures sidebar is visible.
    /// Use this for all tests that need sidebar navigation.
    func launchAppWithSidebar() -> (app: XCUIApplication, window: XCUIElement)? {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { return nil }
        ensureSidebarVisible(in: window)
        return (app, window)
    }

    func ensureSidebarVisible(in window: XCUIElement) {
        // NavigationSplitView may collapse the sidebar on launch.
        // If "Show Sidebar" button exists, tap it to reveal sidebar items.
        let showSidebarButton = window.buttons["Show Sidebar"]
        if showSidebarButton.waitForExistence(timeout: 2) {
            showSidebarButton.tap()
            sleep(1)
        }
    }

    func findElement(
        in root: XCUIElement,
        identifier: String
    ) -> XCUIElement {
        // Use .matching(identifier:).firstMatch for each type to avoid
        // "multiple matching elements found" errors when toolbar items
        // appear in multiple accessibility contexts.
        let typeQueries: [XCUIElementQuery] = [
            root.buttons,
            root.staticTexts,
            root.otherElements,
            root.cells,
            root.outlines,
            root.outlines.cells
        ]
        for query in typeQueries {
            let match = query.matching(identifier: identifier).firstMatch
            if match.exists {
                return match
            }
        }
        return root.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    // swiftlint:enable test_case_accessibility

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
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No window available"); return
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

// MARK: - Workflow Tests (Workflows 2–11)

extension SwiftLintRuleStudioUITests {

    // MARK: - Workflow 2: Rule Browser Search and Filter

    @MainActor
    func testRuleBrowserSearchAndFilter() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        let searchField = window.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8),
                      "Native search field should appear in toolbar")

        searchField.click()
        searchField.typeText("trailing")

        let fieldValue = searchField.value as? String ?? ""
        XCTAssertEqual(fieldValue, "trailing", "Search field should contain typed text")

        let clearButton = findElement(in: window, identifier: "RuleBrowserClearFiltersButton")
        XCTAssertTrue(clearButton.exists, "RuleBrowserClearFiltersButton should be present")

        let statusFilter = findElement(in: window, identifier: "RuleBrowserStatusFilter")
        XCTAssertTrue(statusFilter.exists, "RuleBrowserStatusFilter should be present")
    }

    // MARK: - Workflow 3: Rule Detail Documentation

    @MainActor
    func testRuleDetailDocumentation() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        guard firstRuleRow.waitForExistence(timeout: 8) else { return }
        firstRuleRow.click()

        let enableToggle = findElement(in: window, identifier: "RuleDetailEnableToggle")
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5),
                      "RuleDetailEnableToggle should appear in rule detail")

        let simulateButton = findElement(in: window, identifier: "RuleDetailSimulateButton")
        XCTAssertTrue(simulateButton.exists, "RuleDetailSimulateButton should be present")
    }

    // MARK: - Workflow 4: Simulate Rule Impact

    @MainActor
    func testSimulateRuleImpact() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        guard firstRuleRow.waitForExistence(timeout: 8) else { return }
        firstRuleRow.click()

        let simulateButton = findElement(in: window, identifier: "RuleDetailSimulateButton")
        XCTAssertTrue(simulateButton.waitForExistence(timeout: 5),
                      "RuleDetailSimulateButton should appear after selecting a rule")
        XCTAssertTrue(simulateButton.isEnabled,
                      "Simulate button should be enabled when a workspace is open")

        simulateButton.tap()

        let progressIndicator = app.progressIndicators.firstMatch
        _ = progressIndicator.waitForExistence(timeout: 5)
    }

}

// MARK: - Workflow 5–11: Additional Workflow Tests
// (Continued in SwiftLintRuleStudioUITestsWorkflows.swift)
