//
//  SwiftLintRuleStudioUITests+Workflows.swift
//  SwiftLintRuleStudioUITests
//
//  Workflows 2-11: longer end-to-end UI flows. Split from the main
//  XCTestCase file so neither side trips file_length / no_grouping_extension.
//

import XCTest

extension SwiftLintRuleStudioUITests {

    /// Navigates to Rules and returns the rules outline, having proved it arrived.
    /// `outlines[0]` is the sidebar; `outlines[1]` is the rule list.
    @MainActor
    private func showRules(_ window: XCUIElement) -> XCUIElement {
        findElement(in: window, identifier: "SidebarRulesLink").click()
        assertShowing(
            window,
            present: Marker.rules,
            absent: Marker.violations + Marker.audit,
            "Rules"
        )
        let outline = window.outlines.element(boundBy: 1)
        XCTAssertTrue(outline.waitForExistence(timeout: 8), "Rule list should exist")
        return outline
    }

    // MARK: - Workflow 2: Rule Browser Search and Filter

    @MainActor
    func testRuleBrowserSearchAndFilter() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }
        let rulesOutline = showRules(window)
        let sidebar = window.outlines.element(boundBy: 0)

        let unfilteredCount = rulesOutline.cells.count
        XCTAssertGreaterThan(unfilteredCount, 1, "Rule list should be populated before filtering")
        let sidebarCount = sidebar.cells.count

        let searchField = window.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8),
                      "Native search field should appear in toolbar")
        searchField.click()
        searchField.typeText("trailing")

        XCTAssertEqual(searchField.value as? String, "trailing",
                       "Search field should contain typed text")

        // The point of the test: the *list* has to narrow. Asserting only that the
        // text field echoes what was typed passes even when filtering is dead.
        let filteredCount = waitForCellCountChange(rulesOutline, from: unfilteredCount)
        XCTAssertLessThan(filteredCount, unfilteredCount,
                          "Searching should reduce the rule list from \(unfilteredCount) rows")
        XCTAssertGreaterThan(filteredCount, 0,
                             "'trailing' should still match some rules")
        XCTAssertEqual(sidebar.cells.count, sidebarCount,
                       "Filtering the rule list should not disturb the sidebar")

        XCTAssertTrue(findElement(in: window, identifier: "RuleBrowserClearFiltersButton").exists,
                      "RuleBrowserClearFiltersButton should be present")
        XCTAssertTrue(findElement(in: window, identifier: "RuleBrowserStatusFilter").exists,
                      "RuleBrowserStatusFilter should be present")
    }

    // MARK: - Workflow 3: Rule Detail Documentation

    @MainActor
    func testRuleDetailDocumentation() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }
        let rulesOutline = showRules(window)

        // These were `guard ... else { return }`, so the test reported success when
        // the rule list failed to load and nothing was ever inspected.
        let firstRuleRow = rulesOutline.cells.firstMatch
        XCTAssertTrue(firstRuleRow.waitForExistence(timeout: 8),
                      "Rule list should contain at least one rule to select")
        firstRuleRow.click()

        let enableToggle = findElement(in: window, identifier: "RuleDetailEnableToggle")
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 8),
                      "RuleDetailEnableToggle should appear in rule detail")
        XCTAssertTrue(findElement(in: window, identifier: "RuleDetailSimulateButton").exists,
                      "RuleDetailSimulateButton should be present")

        // The test is named for documentation, so assert the documentation is
        // actually rendered rather than only the controls beside it.
        for section in ["Description", "Why This Matters", "Configuration", "Current Violations"] {
            XCTAssertTrue(text(in: window, section).waitForExistence(timeout: 5),
                          "Rule detail should render its '\(section)' section")
        }
    }

    // MARK: - Workflow 4: Simulate Rule Impact

    @MainActor
    func testSimulateRuleImpact() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }
        let rulesOutline = showRules(window)

        let firstRuleRow = rulesOutline.cells.firstMatch
        XCTAssertTrue(firstRuleRow.waitForExistence(timeout: 8),
                      "Rule list should contain at least one rule to simulate")
        firstRuleRow.click()

        let simulateButton = findElement(in: window, identifier: "RuleDetailSimulateButton")
        XCTAssertTrue(simulateButton.waitForExistence(timeout: 8),
                      "RuleDetailSimulateButton should appear after selecting a rule")
        XCTAssertTrue(simulateButton.isEnabled,
                      "Simulate button should be enabled when a workspace is open")

        XCTAssertEqual(app.sheets.count, 0, "No sheet should be open before simulating")
        simulateButton.click()

        // Simulating presents a sheet. The old version clicked and then discarded
        // `waitForExistence`, so the click's effect was never checked at all.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15),
                      "Simulating should present the Impact Simulation sheet")
        for label in ["Impact Simulation", "Summary", "Simulation Time"] {
            XCTAssertTrue(text(in: sheet, label).waitForExistence(timeout: 10),
                          "Simulation sheet should report '\(label)'")
        }

        let close = sheet.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Sheet should offer a Close button")
        close.click()
        let gone = NSPredicate(format: "exists == false")
        let dismissed = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: gone, object: sheet)],
            timeout: 10
        )
        XCTAssertEqual(dismissed, .completed, "Close should dismiss the simulation sheet")
    }

}
