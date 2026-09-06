//
//  TagResolutionMeasurementTests.swift
//  SwiftLintRuleStudioUITests
//
//  Does `.tag()` still reach its `List` from inside an extracted `View` struct?
//
//  See `TagResolutionHarnessView` for why this needs a click rather than an inspection: the tag is
//  *declared* in both shapes, so reading the view tree finds it either way, and only SwiftUI's own
//  resolution decides whether selecting the row writes to the binding.
//
//  This is deliberately a dedicated test rather than an assertion bolted onto a workflow test.
//  The workflow suite navigates, loads and looks elements up by index, and has two known flakes;
//  a measurement that has to distinguish "the gate is needed" from "the suite is noisy" cannot be
//  built on top of it. This launches, clicks twice, and asserts — no navigation, no waiting on
//  data, no index-based lookup.
//

import XCTest

final class TagResolutionMeasurementTests: XCTestCase {

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launchEnvironment["UI_TEST_TAG_HARNESS"] = "1"
        app.launch()
        return app
    }

    /// Clicks the row named `cell` and returns what `label` then reads.
    private func selectSecondRow(
        in app: XCUIApplication, cell: String, label: String
    ) -> String {
        let row = app.staticTexts[cell]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(cell) never appeared")
        row.click()

        let readout = app.staticTexts[label]
        XCTAssertTrue(readout.waitForExistence(timeout: 10), "\(label) never appeared")
        // The click and the binding write are not synchronous; poll rather than sleep.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, readout.value as? String == "selected-none" {
            usleep(100_000)
        }
        return (readout.value as? String) ?? readout.label
    }

    /// The control. If this fails the harness is wrong, not SwiftUI.
    func testInlineTagResolvesSelection() {
        let app = launchHarness()
        let result = selectSecondRow(
            in: app, cell: "inline-two", label: "InlineSelection"
        )
        XCTAssertEqual(
            result, "selected-202",
            "An inline .tag() did not resolve — the harness is measuring the wrong thing"
        )
    }

    /// The negative control, and the reason to believe the other two.
    ///
    /// Rows with no tag at all cannot resolve a selection, so this readout must stay
    /// `selected-none`. If it does not, the harness is reporting selection from something other
    /// than the tag — positional identity, say — and the two measurements above would pass
    /// whatever SwiftUI did with tags.
    func testUntaggedRowsResolveNothing() {
        let app = launchHarness()
        let result = selectSecondRow(
            in: app, cell: "untagged-two", label: "UntaggedSelection"
        )
        XCTAssertEqual(
            result, "selected-none",
            "Untagged rows resolved a selection, so this suite cannot tell tag resolution from a "
                + "positional fallback and its other results mean nothing"
        )
    }

    /// The measurement. A tag applied inside an extracted `View` struct.
    func testExtractedTagResolvesSelection() {
        let app = launchHarness()
        let result = selectSecondRow(
            in: app, cell: "extracted-two", label: "ExtractedSelection"
        )
        XCTAssertEqual(
            result, "selected-202",
            "A .tag() inside an extracted View did not resolve, so extracting a tagged row out of "
                + "a selectable List breaks selection — Computed Property View must not report "
                + "that shape"
        )
    }
}
