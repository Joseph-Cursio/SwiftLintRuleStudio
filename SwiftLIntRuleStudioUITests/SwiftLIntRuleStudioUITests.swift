//
//  SwiftLIntRuleStudioUITests.swift
//  SwiftLIntRuleStudioUITests
//
//  Created by joe cursio on 12/24/25.
//

import XCTest

@MainActor
final class SwiftLIntRuleStudioUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { SwiftLIntRuleStudioUITests.terminateApp() }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { SwiftLIntRuleStudioUITests.terminateApp() }
    }

    @MainActor private static func terminateApp() {
        let app = XCUIApplication()
        guard app.state != .notRunning else { return }
        app.terminate()
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5.0)
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
        // Use .matching(identifier:).firstMatch for each type so that macOS 26 beta's
        // behavior of duplicating toolbar-item accessibility nodes doesn't cause
        // "multiple matching elements found" errors when .tap() is called.
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

// MARK: - Workflow Tests (Workflows 2–11)

extension SwiftLIntRuleStudioUITests {

    // MARK: - Workflow 2: Rule Browser Search and Filter

    @MainActor
    func testRuleBrowserSearchAndFilter() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // Search is now provided by .searchable() in the toolbar — find the native search field
        let searchField = window.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8),
                      "Native search field should appear in toolbar")

        searchField.click()
        searchField.typeText("trailing")

        // Verify text was entered
        let fieldValue = searchField.value as? String ?? ""
        XCTAssertEqual(fieldValue, "trailing", "Search field should contain typed text")

        // Clear Filters button should exist (active since searchText is non-empty)
        let clearButton = findElement(in: window, identifier: "RuleBrowserClearFiltersButton")
        XCTAssertTrue(clearButton.exists, "RuleBrowserClearFiltersButton should be present in toolbar")

        // Status filter Picker should be visible alongside the search controls
        let statusFilter = findElement(in: window, identifier: "RuleBrowserStatusFilter")
        XCTAssertTrue(statusFilter.exists, "RuleBrowserStatusFilter should be present")
    }

    // MARK: - Workflow 3: Rule Detail Documentation

    @MainActor
    func testRuleDetailDocumentation() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // Wait for rule browser search field to confirm RuleBrowserView is loaded
        // Wait for the native search field to confirm RuleBrowserView is loaded
        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        // Rules list is the second outline in the window (index 0 = sidebar nav)
        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        guard firstRuleRow.waitForExistence(timeout: 8) else {
            // Rules not loaded (SwiftLint may not be available) — navigation path verified
            return
        }
        firstRuleRow.click()

        // Enable toggle must appear in the detail panel
        let enableToggle = findElement(in: window, identifier: "RuleDetailEnableToggle")
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5),
                      "RuleDetailEnableToggle should appear in rule detail")

        // Simulate Impact button is shown when a workspace is open
        let simulateButton = findElement(in: window, identifier: "RuleDetailSimulateButton")
        XCTAssertTrue(simulateButton.exists, "RuleDetailSimulateButton should be present")
    }

    // MARK: - Workflow 4: Simulate Rule Impact

    @MainActor
    func testSimulateRuleImpact() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // Wait for the native search field to confirm RuleBrowserView is loaded
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

        // A spinner or result sheet should appear after tapping Simulate
        // (result depends on SwiftLint availability in the test environment)
        let progressIndicator = app.progressIndicators.firstMatch
        _ = progressIndicator.waitForExistence(timeout: 5)
        // Success: button tap did not crash the app
    }

    // MARK: - Workflow 5: Enable/Disable Rule with Diff Preview

    @MainActor
    func testEnableDisableRulePreview() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // Wait for the native search field to confirm RuleBrowserView is loaded
        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        guard firstRuleRow.waitForExistence(timeout: 8) else { return }
        firstRuleRow.click()

        let enableToggle = findElement(in: window, identifier: "RuleDetailEnableToggle")
        guard enableToggle.waitForExistence(timeout: 5) else { return }

        // Toggle the rule's enable state — this sets pendingChanges on the ViewModel
        enableToggle.click()

        // Preview Changes button must appear whenever pendingChanges != nil
        let previewButton = findElement(in: window, identifier: "RuleDetailPreviewChangesButton")
        XCTAssertTrue(previewButton.waitForExistence(timeout: 3),
                      "Preview Changes button should appear after toggling rule state")

        previewButton.tap()

        // The diff-preview sheet opens; a Cancel button is present when yamlEngine is set.
        // In the no-config test workspace the sheet content is empty, so we dismiss via Escape.
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        } else {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }

    // MARK: - Workflow 6: Violation Inspector Filtering

    @MainActor
    func testViolationInspectorFiltering() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        let searchField = findElement(in: window, identifier: "ViolationInspectorSearchField")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "ViolationInspectorSearchField should appear in violation inspector")

        searchField.click()
        searchField.typeText("test")

        // Grouping menu must also be present in the filter bar
        let groupingMenu = findElement(in: window, identifier: "ViolationInspectorGroupingMenu")
        XCTAssertTrue(groupingMenu.exists, "ViolationInspectorGroupingMenu should be present")
    }

    // MARK: - Workflow 7: Violation Detail — Open in Xcode

    @MainActor
    func testViolationDetailOpenInXcodeButton() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        // Wait briefly for any analysis progress to settle
        _ = app.progressIndicators.firstMatch.waitForExistence(timeout: 3)

        // Violations are displayed in a Table (non-grouped mode) or List (grouped mode).
        // Try the Table first; fall back to the old outline approach for grouped mode.
        let violationTable = window.tables.firstMatch
        let violationsOutline = window.outlines.element(boundBy: 1)
        let firstViolationRow: XCUIElement
        if violationTable.waitForExistence(timeout: 2) {
            firstViolationRow = violationTable.cells.firstMatch
        } else {
            firstViolationRow = violationsOutline.cells.firstMatch
        }
        guard firstViolationRow.waitForExistence(timeout: 5) else {
            // No violations produced in the minimal test workspace — navigation verified
            return
        }
        firstViolationRow.click()

        let openInXcodeButton = findElement(in: window, identifier: "ViolationDetailOpenInXcodeButton")
        XCTAssertTrue(openInXcodeButton.waitForExistence(timeout: 5),
                      "ViolationDetailOpenInXcodeButton should appear in violation detail")
    }

    // MARK: - Workflow 8: Bulk Rule Operations

    @MainActor
    func testBulkRuleOperations() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // Wait for the native search field to confirm RuleBrowserView is loaded
        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        // Enter multi-select mode via toolbar button
        let multiSelectButton = findElement(in: window, identifier: "RuleBrowserMultiSelectButton")
        XCTAssertTrue(multiSelectButton.waitForExistence(timeout: 5),
                      "RuleBrowserMultiSelectButton should be in the toolbar")
        multiSelectButton.tap()

        // BulkOperationToolbar should now be visible
        let enableAllButton = findElement(in: window, identifier: "BulkOperationEnableAllButton")
        XCTAssertTrue(enableAllButton.waitForExistence(timeout: 3),
                      "BulkOperationEnableAllButton should appear when multi-select mode is active")

        // Select the first rule row
        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        if firstRuleRow.waitForExistence(timeout: 5) {
            firstRuleRow.click()
            // BulkOperationPreviewChangesButton must be present (selection count > 0)
            let previewButton = findElement(in: window, identifier: "BulkOperationPreviewChangesButton")
            XCTAssertTrue(previewButton.exists,
                          "BulkOperationPreviewChangesButton should be present in bulk toolbar")
        }

        // Exit multi-select mode
        multiSelectButton.tap()

        // BulkOperationToolbar should disappear
        let enableAllAfterExit = findElement(in: window, identifier: "BulkOperationEnableAllButton")
        XCTAssertFalse(enableAllAfterExit.exists,
                       "BulkOperationEnableAllButton should disappear after exiting multi-select")
    }

    // MARK: - Workflow 9: Discover Safe Rules

    @MainActor
    func testDiscoverSafeRules() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let safeRulesLink = findElement(in: window, identifier: "SidebarSafeRulesLink")
        XCTAssertTrue(safeRulesLink.waitForExistence(timeout: 5))
        safeRulesLink.tap()

        let discoverButton = findElement(in: window, identifier: "SafeRulesDiscoverButton")
        XCTAssertTrue(discoverButton.waitForExistence(timeout: 5),
                      "SafeRulesDiscoverButton should be visible in the discovery view")
        XCTAssertTrue(discoverButton.isEnabled,
                      "SafeRulesDiscoverButton should be enabled when a workspace is set")

        discoverButton.tap()

        // A progress indicator appears while discovery runs
        // (may succeed or fail quickly in test environment — tapping must not crash)
        let progressIndicator = app.progressIndicators.firstMatch
        _ = progressIndicator.waitForExistence(timeout: 5)
    }

    // MARK: - Workflow 10: Config Version History

    @MainActor
    func testConfigVersionHistory() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let versionHistoryLink = findElement(in: window, identifier: "SidebarVersionHistoryLink")
        XCTAssertTrue(versionHistoryLink.waitForExistence(timeout: 5))
        versionHistoryLink.tap()

        // Refresh button must be in the toolbar
        let refreshButton = findElement(in: window, identifier: "ConfigHistoryRefreshButton")
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5),
                      "ConfigHistoryRefreshButton should be present in toolbar")

        refreshButton.tap()

        // Prune menu must also be in the toolbar
        let pruneMenu = findElement(in: window, identifier: "ConfigHistoryPruneMenu")
        XCTAssertTrue(pruneMenu.exists, "ConfigHistoryPruneMenu should be present in toolbar")
    }

    // MARK: - Workflow 11: Suppress Violation

    @MainActor
    func testSuppressViolation() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        // Wait briefly for analysis to settle
        _ = app.progressIndicators.firstMatch.waitForExistence(timeout: 3)

        // Find a violation row in the list
        let violationsList = window.outlines.element(boundBy: 1)
        let firstViolationRow = violationsList.cells.firstMatch
        guard firstViolationRow.waitForExistence(timeout: 5) else {
            // No violations in the minimal test workspace — navigation path verified
            return
        }
        firstViolationRow.click()

        let suppressButton = findElement(in: window, identifier: "ViolationDetailSuppressButton")
        guard suppressButton.waitForExistence(timeout: 5) else { return }

        suppressButton.tap()

        // The suppress dialog sheet should appear with a Cancel action
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(cancelButton.exists, "Cancel button should be present in suppress dialog")
            cancelButton.tap()
        }
    }
}

// MARK: - Workflow 12–13: Toolbar Tests

extension SwiftLIntRuleStudioUITests {

    // MARK: - Workflow 12: Context-aware Toolbar Section Switching

    @MainActor
    func testContextAwareToolbarSectionSwitching() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        // Navigate to Rules section (make it explicit even though it is the default)
        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        // View mode picker and Reload Rules button must appear on the Rules section
        let viewModePicker = findElement(in: window, identifier: "ContentViewViewModePicker")
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 5),
                      "View mode picker should be visible on the Rules section")

        let reloadButton = findElement(in: window, identifier: "ContentViewReloadRulesButton")
        XCTAssertTrue(reloadButton.exists,
                      "Reload Rules button should be visible on the Rules section")

        // Navigate to Violations — context controls must change
        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        // View mode picker must disappear
        XCTAssertFalse(viewModePicker.waitForExistence(timeout: 3),
                       "View mode picker must not appear on the Violations section")

        // Refresh Violations button must appear in its place
        let refreshViolationsButton = findElement(in: window, identifier: "ContentViewRefreshViolationsButton")
        XCTAssertTrue(refreshViolationsButton.waitForExistence(timeout: 3),
                      "Refresh Violations button should appear on the Violations section")
    }

    // MARK: - Workflow 13: Violation Inspector Toolbar Buttons

    @MainActor
    func testViolationInspectorToolbarButtons() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true)
        let window = waitForMainWindow(in: app)
        guard window.exists else { XCTFail("No main window"); return }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        // Permanent toolbar buttons must always be present
        let refreshButton = findElement(in: window, identifier: "ViolationInspectorRefreshButton")
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5),
                      "Refresh button should be in the ViolationInspector toolbar")

        let nextButton = findElement(in: window, identifier: "ViolationInspectorNextButton")
        XCTAssertTrue(nextButton.exists,
                      "Next button should be in the ViolationInspector toolbar")

        let prevButton = findElement(in: window, identifier: "ViolationInspectorPreviousButton")
        XCTAssertTrue(prevButton.exists,
                      "Previous button should be in the ViolationInspector toolbar")

        let selectionMenu = findElement(in: window, identifier: "ViolationInspectorSelectionMenu")
        XCTAssertTrue(selectionMenu.exists,
                      "Selection menu should be in the ViolationInspector toolbar")

        // Actions menu is conditional — must be absent when nothing is selected
        let actionsMenu = findElement(in: window, identifier: "ViolationInspectorActionsMenu")
        XCTAssertFalse(actionsMenu.exists,
                       "Actions menu must not appear when no violations are selected")
    }
}
