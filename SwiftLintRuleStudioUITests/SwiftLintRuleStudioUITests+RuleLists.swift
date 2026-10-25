//
//  SwiftLintRuleStudioUITests+RuleLists.swift
//  SwiftLintRuleStudioUITests
//
//  Issue #83 end to end: a workspace whose `.swiftlint.yml` SwiftLint rejects shows the
//  rule-lists banner, and its reviewed fix clears it.
//

import XCTest

extension SwiftLintRuleStudioUITests {

    /// The shape issue #83 reported, cut down: opt-in rules listed under only_rules and
    /// opt_in_rules both, and an analyzer rule in only_rules and analyzer_rules both.
    private static let conflictedConfig = """
    included:
      - Sources
    only_rules:
      - force_cast
      - empty_count
      - unused_import
    opt_in_rules:
      - empty_count
    analyzer_rules:
      - unused_import

    """

    @MainActor
    func testRuleListsBannerOffersAndAppliesTheFix() throws {
        let app = launchApp(skipOnboarding: true, createWorkspace: true, workspaceConfig: Self.conflictedConfig)
        let window = waitForMainWindow(in: app)
        XCTAssertTrue(window.exists, "No main window")

        let banner = window.descendants(matching: .any).matching(identifier: "RuleListsProblemBanner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "A config SwiftLint rejects should raise the banner")

        let reviewFix = window.buttons.matching(identifier: "RuleListsProblemReviewFixButton").firstMatch
        XCTAssertTrue(reviewFix.waitForExistence(timeout: 5), "The banner should offer the fix")
        reviewFix.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Review Fix should open the diff preview")
        XCTAssertTrue(sheet.buttons["Save Changes"].waitForExistence(timeout: 5), "The preview should offer Save")
        // Saved with the button's own shortcut, ⌘↩: the 700×500 preview can hang off the bottom of the
        // display, and XCUITest won't click a button it reports as outside every screen.
        app.typeKey(.return, modifierFlags: .command)

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "The fix should clear the banner")
    }
}
