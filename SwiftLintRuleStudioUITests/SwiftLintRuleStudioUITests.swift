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
            showSidebarButton.click()
            sleep(1)
        }
    }

    // Interactions use `click()`, not `tap()`. On the macOS 27 SDK `tap()` is a
    // silent no-op against this app's SwiftUI controls: the element reports
    // `exists`, `isEnabled` and `isHittable` all true, the call returns without
    // error, and nothing happens. `testOnboardingFlow` caught it because it
    // asserts on the step it navigates to; the other flows kept passing only
    // because their assertions held without the tap ever landing. `click()` is
    // the macOS-native API and works on both 6.3.3 and 6.4.
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

    /// Text in this app's SwiftUI views surfaces as `value` on macOS, not `label`,
    /// so match on either rather than using subscript lookup.
    func text(in root: XCUIElement, _ string: String) -> XCUIElement {
        root.staticTexts
            .matching(NSPredicate(format: "label == %@ OR value == %@", string, string))
            .firstMatch
    }

    /// Asserts the destination identified by `present` is on screen and that every
    /// other section's marker is gone. Checking the absences is the point: a
    /// navigation that never happened leaves the previous screen's markers behind,
    /// which is exactly what a presence-only assertion cannot see.
    func assertShowing(
        _ window: XCUIElement,
        present: [String],
        absent: [String],
        _ destination: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let first = present.first else { return }
        XCTAssertTrue(
            findElement(in: window, identifier: first).waitForExistence(timeout: 8),
            "\(destination) should be showing, but \(first) never appeared",
            file: file, line: line
        )
        for ident in present.dropFirst() {
            XCTAssertTrue(
                findElement(in: window, identifier: ident).exists,
                "\(destination) should be showing, but \(ident) is missing",
                file: file, line: line
            )
        }
        for ident in absent {
            XCTAssertFalse(
                findElement(in: window, identifier: ident).exists,
                "\(ident) is still on screen, so navigation to \(destination) did not happen",
                file: file, line: line
            )
        }
    }

    /// Polls until the outline reports a different row count, so filtering
    /// assertions wait on the list actually changing rather than on a fixed sleep.
    @discardableResult
    func waitForCellCountChange(
        _ outline: XCUIElement,
        from original: Int,
        timeout: TimeInterval = 10
    ) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var current = outline.cells.count
        while current == original && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            current = outline.cells.count
        }
        return current
    }

    /// Markers unique to each sidebar destination, used to prove navigation landed.
    enum Marker {
        static let rules = [
            "RuleBrowserClearFiltersButton",
            "RuleBrowserStatusFilter",
            "RuleBrowserMultiSelectButton"
        ]
        static let violations = [
            "ViolationInspectorRefreshButton",
            "ViolationInspectorGroupingMenu",
            "ViolationInspectorSearchField"
        ]
        static let audit = ["RunAuditButton"]
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
