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

    // MARK: - Workflow 5: Rule Presets

    /// A preset filters the list by rule identifier, so one SwiftLint doesn't have matches
    /// nothing and the list comes up short. Code Style named `operator_whitespace`, an old
    /// alias, and so never showed `function_name_whitespace`.
    @MainActor
    func testCodeStylePresetShowsEveryRuleItNames() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }
        let rulesOutline = showRules(window)
        let unfilteredCount = rulesOutline.cells.count
        XCTAssertGreaterThan(unfilteredCount, 12, "Rule list should be populated before choosing a preset")

        let presets = window.menuButtons["Presets"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 8), "The Presets menu should be in the toolbar")
        presets.click()
        // "Code Style" is also the preset's category, and the menu lists its section header
        // first under the same title. Headers report enabled on macOS 27, and a SwiftUI
        // menu item's accessibilityIdentifier doesn't reach the native menu, so tell them
        // apart by the action AppKit gives the preset's button.
        let codeStyle = app.menuItems
            .matching(NSPredicate(format: "title == %@ AND identifier == %@", "Code Style", "menuAction:"))
            .firstMatch
        XCTAssertTrue(codeStyle.waitForExistence(timeout: 5), "The Presets menu should offer Code Style")
        codeStyle.click()

        let filteredCount = waitForCellCountChange(rulesOutline, from: unfilteredCount)
        XCTAssertEqual(filteredCount, 12, "Code Style names 12 rules, and every one should be listed")
        XCTAssertTrue(text(in: rulesOutline, "function_name_whitespace").waitForExistence(timeout: 5),
                      "Code Style should show function_name_whitespace")
    }
}
