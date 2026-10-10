//
//  SwiftLintRuleStudioUITests+RuleHistory.swift
//  SwiftLintRuleStudioUITests
//
//  Version Check and the Migration Assistant, end to end, against the installed
//  SwiftLint. The rule history behind them once renamed live rules, renamed
//  removed rules to rules that never existed, and offered removed rules as new
//  ones to enable.
//

import XCTest

extension SwiftLintRuleStudioUITests {

    /// One rule for each kind of entry the history got wrong: two live rules it renamed,
    /// a rule removed in favor of a compiler warning, and an alias it was missing.
    static let ruleHistoryConfig = """
    disabled_rules:
      - multiple_closures_with_trailing_closure
      - generic_type_name
    opt_in_rules:
      - unused_capture_list
      - if_let_shadowing
    """

    /// Static texts matching any of `labels` exactly, by label or value.
    private func texts(in root: XCUIElement, matching labels: [String]) -> XCUIElementQuery {
        root.staticTexts.matching(NSPredicate(format: "label IN %@ OR value IN %@", labels, labels))
    }

    /// Static texts containing `fragment`, by label or value.
    private func texts(in root: XCUIElement, containing fragment: String) -> XCUIElementQuery {
        root.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fragment, fragment)
        )
    }

    /// The content scroll view showing `heading`. `window.scrollViews.firstMatch` is the
    /// sidebar, and other sections' views can linger in the tree, so a section's checks
    /// look inside its own scroll view.
    private func scrollView(in window: XCUIElement, showing heading: String) -> XCUIElement {
        window.scrollViews
            .containing(NSPredicate(format: "label == %@ OR value == %@", heading, heading))
            .firstMatch
    }

    /// Scrolls through `scrollView` both ways and returns which of `labels` were on screen
    /// at some point. The new-rules grid is lazy, so a rule below the fold is not in the
    /// accessibility tree until it scrolls into view.
    private func labelsSeenScrolling(_ scrollView: XCUIElement, for labels: [String]) -> Set<String> {
        var seen: Set<String> = []
        for delta in Array(repeating: -300.0, count: 6) + Array(repeating: 300.0, count: 12) {
            for element in texts(in: scrollView, matching: labels).allElementsBoundByIndex {
                if let value = element.value as? String, labels.contains(value) {
                    seen.insert(value)
                } else {
                    seen.insert(element.label)
                }
            }
            scrollView.scroll(byDeltaX: 0, deltaY: delta)
        }
        return seen
    }

    // MARK: - Version Check

    @MainActor
    func testVersionCheckReportsRealRuleHistory() throws {
        guard let (_, window) = launchAppWithSidebar(swiftLintYML: Self.ruleHistoryConfig) else {
            XCTFail("No main window"); return
        }
        findElement(in: window, identifier: "SidebarVersionCheckLink").click()
        let report = scrollView(in: window, showing: "SwiftLint Version")
        XCTAssertTrue(report.waitForExistence(timeout: 8), "Version Check should be showing")

        // The check runs on appear. if_let_shadowing is deprecated and renamed;
        // unused_capture_list is removed. The two live rules are no issue at all.
        XCTAssertTrue(text(in: report, "3 issues found").waitForExistence(timeout: 30),
                      "Version Check should find exactly three issues")
        XCTAssertTrue(text(in: report, "unused_capture_list").exists,
                      "unused_capture_list should be reported")
        XCTAssertTrue(text(in: report, "Removed in 0.58.0").exists,
                      "unused_capture_list was removed in 0.58.0")
        XCTAssertTrue(text(in: report, "Use: shorthand_optional_binding").exists,
                      "if_let_shadowing should point at shorthand_optional_binding")

        let fixButtons = report.buttons.matching(NSPredicate(format: "label == %@ OR title == %@", "Fix", "Fix"))
        XCTAssertEqual(fixButtons.count, 1, "Only if_let_shadowing should be offered as a rename")

        let wrong = [
            "multiple_closures_with_trailing_closure", "generic_type_name", "trailing_closure", "unused_closure_use"
        ]
        XCTAssertEqual(texts(in: report, matching: wrong).count, 0,
                       "No live rule, or rule that never existed, should be reported")

        // The new rules are sorted, and the grid is three wide: anyobject_protocol would sit
        // beside async_without_await, and opaque_over_existential beside
        // optional_data_string_conversion. Seeing the neighbours proves the spot was rendered.
        let neighbours = ["async_without_await", "optional_data_string_conversion"]
        let removed = ["anyobject_protocol", "opaque_over_existential", "unused_closure_use"]
        let seen = labelsSeenScrolling(report, for: neighbours + removed)
        for rule in neighbours {
            XCTAssertTrue(seen.contains(rule), "New rules should list \(rule)")
        }
        for rule in removed {
            XCTAssertFalse(seen.contains(rule), "New rules should not offer \(rule), which 0.65 doesn't have")
        }
    }

    // MARK: - Migration Assistant

    @MainActor
    func testMigrationPlansOnlyRealRenamesAndRemovals() throws {
        guard let (_, window) = launchAppWithSidebar(swiftLintYML: Self.ruleHistoryConfig) else {
            XCTFail("No main window"); return
        }
        findElement(in: window, identifier: "SidebarMigrationLink").click()

        let field = findElement(in: window, identifier: "MigrationPreviousVersionField")
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Migration should ask for the previous version")
        field.click()
        field.typeText("0.50.0")

        let detect = findElement(in: window, identifier: "MigrationDetectButton")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: detect)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed,
                       "Detect Migrations should enable once a version is entered")
        detect.click()

        let migration = scrollView(in: window, showing: "Version Migration")
        XCTAssertTrue(
            text(in: migration, "Rename 'if_let_shadowing' to 'shorthand_optional_binding'")
                .waitForExistence(timeout: 30),
            "The plan should rename if_let_shadowing"
        )
        XCTAssertTrue(
            text(in: migration, "Remove 'unused_capture_list': Removed after being deprecated. "
                 + "The Swift compiler warns about this instead.").exists,
            "The plan should remove unused_capture_list, not rename it"
        )
        // The rename, the removal, and the new-rules note.
        XCTAssertTrue(text(in: migration, "3 steps").exists, "The plan should have exactly three steps")

        // opaque_over_existential arrived in 0.59.0 and left in 0.59.1, so the new-rules
        // note must not offer it.
        let unmentioned = [
            "multiple_closures_with_trailing_closure", "generic_type_name", "unused_closure_use",
            "opaque_over_existential"
        ]
        for rule in unmentioned {
            XCTAssertEqual(texts(in: migration, containing: rule).count, 0, "The plan should not mention \(rule)")
        }
    }
}
