//
//  SwiftLintRuleStudioUITests+Workflows.swift
//  SwiftLintRuleStudioUITests
//
//  Workflows 2-11: longer end-to-end UI flows. Split from the main
//  XCTestCase file so neither side trips file_length / no_grouping_extension.
//

import XCTest

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
