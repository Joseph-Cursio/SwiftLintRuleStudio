//
//  RulePresetBrowserViewTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the staged preset browser. Its entry point is disclosed but
//  disabled (see Feature.presetBrowser), so these keep it honest while it
//  waits rather than letting it drift out of sync with the catalogue.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite("RulePresetBrowserView")
struct RulePresetBrowserViewTests {

    private static func makeBrowser(
        onPresetSelected: @escaping (RulePreset) -> Void = { _ in }
    ) -> RulePresetBrowserView {
        RulePresetBrowserView(onPresetSelected: onPresetSelected)
    }

    private static func browserContains(_ browser: RulePresetBrowserView, text: String) -> Bool {
        (try? browser.inspect().find(text: text)) != nil
    }

    // MARK: - Filtering

    @Test("No category selected shows every preset")
    func showsAllPresetsWithoutACategory() {
        let presets = RulePresetBrowserView.presets(in: nil)

        #expect(presets.count == RulePresets.allPresets.count)
    }

    @Test("A selected category shows only that category's presets")
    func filtersToSelectedCategory() {
        for category in RulePreset.PresetCategory.allCases {
            let presets = RulePresetBrowserView.presets(in: category)

            #expect(
                presets.allSatisfy { $0.category == category },
                "\(category.rawValue) leaked a preset from another category"
            )
            #expect(presets.count == RulePresets.presets(in: category).count)
        }
    }

    @Test("Filtering by every category in turn accounts for every preset")
    func filteringPartitionsTheCatalogue() {
        let filtered = RulePreset.PresetCategory.allCases
            .flatMap { RulePresetBrowserView.presets(in: $0) }

        #expect(Set(filtered.map(\.id)) == Set(RulePresets.allPresets.map(\.id)))
    }

    // MARK: - Rendering

    @Test("The browser is titled and offers a way out")
    func showsTitleAndCancel() {
        let browser = Self.makeBrowser()

        #expect(Self.browserContains(browser, text: "Categories"))
        #expect((try? browser.inspect().find(button: "Cancel")) != nil)
    }

    @Test("Every category is listed in the sidebar")
    func listsEveryCategory() {
        let browser = Self.makeBrowser()

        for category in RulePreset.PresetCategory.allCases {
            #expect(
                Self.browserContains(browser, text: category.displayName),
                "\(category.rawValue) is missing from the sidebar"
            )
        }
    }

    @Test("Every preset is shown as a card by default")
    func showsEveryPresetCard() {
        let browser = Self.makeBrowser()

        for preset in RulePresets.allPresets {
            #expect(
                Self.browserContains(browser, text: preset.name),
                "\(preset.id) is missing from the grid"
            )
        }
    }

    // MARK: - Selection

    @Test("Choosing a card reports that preset")
    func cardSelectionReportsPreset() throws {
        let target = try #require(RulePresets.allPresets.first)

        nonisolated(unsafe) var chosen: [RulePreset] = []
        let browser = Self.makeBrowser { chosen.append($0) }

        let card = try browser.inspect().find(ViewType.Button.self) { button in
            (try? button.find(text: target.name)) != nil
        }
        try card.tap()

        #expect(chosen.map(\.id) == [target.id])
    }
}
