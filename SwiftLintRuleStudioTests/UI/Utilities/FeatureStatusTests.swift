//
//  FeatureStatusTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the roadmap-status vocabulary the UI uses to disclose that a
//  feature isn't finished.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("FeatureStatus")
struct FeatureStatusTests {

    // MARK: - Available

    @Test("An available feature needs no disclosure")
    func availableDisclosesNothing() {
        let status = FeatureStatus.available

        #expect(status.isAvailable)
        #expect(status.disclosure == nil)
        #expect(status.note == nil)
    }

    // MARK: - Coming soon

    @Test("An unfinished feature is not available and says so")
    func comingSoonDisclosesItself() {
        let status = FeatureStatus.comingSoon(note: "Use the menu meanwhile.")

        #expect(!status.isAvailable)
        #expect(status.disclosure == "Coming in a later release")
        #expect(status.note == "Use the menu meanwhile.")
    }

    @Test("The note is carried through verbatim")
    func comingSoonCarriesItsNote() {
        let note = "A very specific explanation of what to do instead."

        #expect(FeatureStatus.comingSoon(note: note).note == note)
    }

    @Test("Statuses compare by case and note")
    func statusesCompareStructurally() {
        #expect(FeatureStatus.available == .available)
        #expect(FeatureStatus.comingSoon(note: "a") == .comingSoon(note: "a"))
        #expect(FeatureStatus.comingSoon(note: "a") != .comingSoon(note: "b"))
        #expect(FeatureStatus.available != .comingSoon(note: "a"))
    }

    // MARK: - The feature catalogue

    @Test("Every listed feature has a title")
    func everyFeatureIsTitled() {
        for feature in Feature.allCases {
            #expect(!feature.title.isEmpty, "\(feature.rawValue) has no title")
        }
    }

    @Test("Every listed feature is actually unfinished")
    func everyListedFeatureIsUnfinished() {
        // The catalogue exists to disclose incomplete work. A finished feature
        // should be removed from it, not left declaring itself available.
        for feature in Feature.allCases {
            #expect(
                !feature.status.isAvailable,
                "\(feature.rawValue) is available and should be dropped from Feature"
            )
        }
    }

    @Test("Every unfinished feature explains what to do instead")
    func everyUnfinishedFeatureHasANote() {
        for feature in Feature.allCases where !feature.status.isAvailable {
            let note = feature.status.note ?? ""
            #expect(!note.isEmpty, "\(feature.rawValue) discloses nothing useful")
        }
    }

    @Test("The preset browser points users at the menu that already works")
    func presetBrowserNoteNamesTheWorkingPath() throws {
        let note = try #require(Feature.presetBrowser.status.note)

        #expect(note.contains("menu"))
    }
}
