//
//  SwiftLintRuleStudioUITestsWorkflows.swift
//  SwiftLintRuleStudioUITests
//
//  Additional workflow UI tests (split from SwiftLintRuleStudioUITests)
//

import XCTest

// MARK: - Workflow 5–11: Additional Workflow Tests

extension SwiftLintRuleStudioUITests {

    // MARK: - Workflow 5: Enable/Disable Rule with Diff Preview

    @MainActor
    func testEnableDisableRulePreview() throws {
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

        let enableToggle = findElement(in: window, identifier: "RuleDetailEnableToggle")
        guard enableToggle.waitForExistence(timeout: 5) else { return }

        enableToggle.click()

        let previewButton = findElement(in: window, identifier: "RuleDetailPreviewChangesButton")
        XCTAssertTrue(previewButton.waitForExistence(timeout: 3),
                      "Preview Changes button should appear after toggling rule state")

        previewButton.tap()

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
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        let searchField = findElement(in: window, identifier: "ViolationInspectorSearchField")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "ViolationInspectorSearchField should appear")

        searchField.click()
        searchField.typeText("test")

        let groupingMenu = findElement(in: window, identifier: "ViolationInspectorGroupingMenu")
        XCTAssertTrue(groupingMenu.exists, "ViolationInspectorGroupingMenu should be present")
    }

    // MARK: - Workflow 7: Violation Detail — Open in Xcode

    @MainActor
    func testViolationDetailOpenInXcodeButton() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        _ = app.progressIndicators.firstMatch.waitForExistence(timeout: 3)

        let violationTable = window.tables.firstMatch
        let violationsOutline = window.outlines.element(boundBy: 1)
        let firstViolationRow: XCUIElement
        if violationTable.waitForExistence(timeout: 2) {
            firstViolationRow = violationTable.cells.firstMatch
        } else {
            firstViolationRow = violationsOutline.cells.firstMatch
        }
        guard firstViolationRow.waitForExistence(timeout: 5) else { return }
        firstViolationRow.click()

        let openInXcodeButton = findElement(
            in: window, identifier: "ViolationDetailOpenInXcodeButton"
        )
        XCTAssertTrue(openInXcodeButton.waitForExistence(timeout: 5),
                      "ViolationDetailOpenInXcodeButton should appear")
    }

    // MARK: - Workflow 8: Bulk Rule Operations

    @MainActor
    func testBulkRuleOperations() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        let searchField = window.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else { return }

        let multiSelectButton = findElement(
            in: window, identifier: "RuleBrowserMultiSelectButton"
        )
        XCTAssertTrue(multiSelectButton.waitForExistence(timeout: 5),
                      "RuleBrowserMultiSelectButton should be in the toolbar")
        multiSelectButton.tap()

        let enableAllButton = findElement(
            in: window, identifier: "BulkOperationEnableAllButton"
        )
        XCTAssertTrue(enableAllButton.waitForExistence(timeout: 3),
                      "BulkOperationEnableAllButton should appear in multi-select mode")

        let rulesOutline = window.outlines.element(boundBy: 1)
        let firstRuleRow = rulesOutline.cells.firstMatch
        if firstRuleRow.waitForExistence(timeout: 5) {
            firstRuleRow.click()
            let previewButton = findElement(
                in: window, identifier: "BulkOperationPreviewChangesButton"
            )
            XCTAssertTrue(previewButton.exists,
                          "BulkOperationPreviewChangesButton should be present")
        }

        multiSelectButton.tap()

        let enableAllAfterExit = findElement(
            in: window, identifier: "BulkOperationEnableAllButton"
        )
        XCTAssertFalse(enableAllAfterExit.exists,
                       "BulkOperationEnableAllButton should disappear after exit")
    }

    // MARK: - Workflow 9: Rule Audit

    @MainActor
    func testRuleAudit() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let ruleAuditLink = findElement(in: window, identifier: "SidebarRuleAuditLink")
        XCTAssertTrue(ruleAuditLink.waitForExistence(timeout: 5))
        ruleAuditLink.tap()

        let auditButton = findElement(in: window, identifier: "RunAuditButton")
        XCTAssertTrue(auditButton.waitForExistence(timeout: 5),
                      "RunAuditButton should be visible")
        XCTAssertTrue(auditButton.isEnabled,
                      "RunAuditButton should be enabled")

        auditButton.tap()

        let progressIndicator = app.progressIndicators.firstMatch
        _ = progressIndicator.waitForExistence(timeout: 5)
    }

    // MARK: - Workflow 10: Config Version History

    @MainActor
    func testConfigVersionHistory() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let versionHistoryLink = findElement(
            in: window, identifier: "SidebarVersionHistoryLink"
        )
        XCTAssertTrue(versionHistoryLink.waitForExistence(timeout: 5))
        versionHistoryLink.tap()

        let refreshButton = findElement(in: window, identifier: "ConfigHistoryRefreshButton")
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5),
                      "ConfigHistoryRefreshButton should be present")

        refreshButton.tap()

        let pruneMenu = findElement(in: window, identifier: "ConfigHistoryPruneMenu")
        XCTAssertTrue(pruneMenu.exists, "ConfigHistoryPruneMenu should be present")
    }

    // MARK: - Workflow 11: Suppress Violation

    @MainActor
    func testSuppressViolation() throws {
        guard let (app, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        _ = app.progressIndicators.firstMatch.waitForExistence(timeout: 3)

        let violationsList = window.outlines.element(boundBy: 1)
        let firstViolationRow = violationsList.cells.firstMatch
        guard firstViolationRow.waitForExistence(timeout: 5) else { return }
        firstViolationRow.click()

        let suppressButton = findElement(
            in: window, identifier: "ViolationDetailSuppressButton"
        )
        guard suppressButton.waitForExistence(timeout: 5) else { return }

        suppressButton.tap()

        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(cancelButton.exists, "Cancel button should be in suppress dialog")
            cancelButton.tap()
        }
    }
}

// MARK: - Workflow 12–13: Toolbar Tests

extension SwiftLintRuleStudioUITests {

    // MARK: - Workflow 12: Context-aware Toolbar Section Switching

    @MainActor
    func testContextAwareToolbarSectionSwitching() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let rulesLink = findElement(in: window, identifier: "SidebarRulesLink")
        XCTAssertTrue(rulesLink.waitForExistence(timeout: 5))
        rulesLink.tap()

        let reloadButton = findElement(in: window, identifier: "ContentViewReloadRulesButton")
        XCTAssertTrue(reloadButton.exists,
                      "Reload Rules button should be visible on the Rules section")

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        let refreshViolationsButton = findElement(
            in: window, identifier: "ContentViewRefreshViolationsButton"
        )
        XCTAssertTrue(refreshViolationsButton.waitForExistence(timeout: 3),
                      "Refresh Violations button should appear on the Violations section")
    }

    // MARK: - Workflow 13: Violation Inspector Toolbar Buttons

    @MainActor
    func testViolationInspectorToolbarButtons() throws {
        guard let (_, window) = launchAppWithSidebar() else {
            XCTFail("No main window"); return
        }

        let violationsLink = findElement(in: window, identifier: "SidebarViolationsLink")
        XCTAssertTrue(violationsLink.waitForExistence(timeout: 5))
        violationsLink.tap()

        let refreshButton = findElement(
            in: window, identifier: "ViolationInspectorRefreshButton"
        )
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5),
                      "Refresh button should be in the ViolationInspector toolbar")

        let nextButton = findElement(in: window, identifier: "ViolationInspectorNextButton")
        XCTAssertTrue(nextButton.exists, "Next button should be in the toolbar")

        let prevButton = findElement(
            in: window, identifier: "ViolationInspectorPreviousButton"
        )
        XCTAssertTrue(prevButton.exists, "Previous button should be in the toolbar")

        let selectionMenu = findElement(
            in: window, identifier: "ViolationInspectorSelectionMenu"
        )
        XCTAssertTrue(selectionMenu.exists, "Selection menu should be in the toolbar")

        let actionsMenu = findElement(
            in: window, identifier: "ViolationInspectorActionsMenu"
        )
        XCTAssertFalse(actionsMenu.exists,
                       "Actions menu must not appear when no violations are selected")
    }
}
