//
//  RulePresetPickerTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the preset menu: every preset is offered under its category,
//  and choosing one hands that preset back to the caller.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite("RulePresetPicker")
struct RulePresetPickerTests {

    private static func makePicker(
        onPresetSelected: @escaping (RulePreset) -> Void = { _ in }
    ) -> RulePresetPicker {
        RulePresetPicker(onPresetSelected: onPresetSelected)
    }

    private static func menuContains(_ picker: RulePresetPicker, text: String) -> Bool {
        (try? picker.inspect().find(text: text)) != nil
    }

    // MARK: - Menu contents

    @Test("The menu is labelled Presets")
    func menuIsLabelled() {
        #expect(Self.menuContains(Self.makePicker(), text: "Presets"))
    }

    @Test("Every preset category is offered as a section")
    func offersEveryCategory() {
        let picker = Self.makePicker()

        for category in RulePreset.PresetCategory.allCases {
            #expect(
                Self.menuContains(picker, text: category.displayName),
                "category \(category.rawValue) is missing from the menu"
            )
        }
    }

    @Test("Every preset is offered as an item")
    func offersEveryPreset() {
        let picker = Self.makePicker()

        for preset in RulePresets.allPresets {
            #expect(
                Self.menuContains(picker, text: preset.name),
                "preset \(preset.id) is missing from the menu"
            )
        }
    }

    @Test("The menu offers exactly the presets the catalogue defines")
    func offersNoPresetsBeyondTheCatalogue() throws {
        let picker = Self.makePicker()
        let buttons = try picker.inspect().findAll(ViewType.Button.self)

        // One button per preset, plus the browser's entry point.
        #expect(buttons.count == RulePresets.allPresets.count + 1)
    }

    // MARK: - Unfinished browser disclosure

    @Test("The browser's entry point is shown rather than hidden")
    func showsBrowserEntryPoint() {
        #expect(Self.menuContains(Self.makePicker(), text: Feature.presetBrowser.title))
    }

    @Test("The browser is labelled as unfinished")
    func disclosesBrowserIsUnfinished() throws {
        let disclosure = try #require(Feature.presetBrowser.status.disclosure)

        #expect(Self.menuContains(Self.makePicker(), text: disclosure))
    }

    @Test("Choosing the unfinished browser reports no preset")
    func browserEntrySelectsNothing() throws {
        nonisolated(unsafe) var chosen: [RulePreset] = []
        let picker = Self.makePicker { chosen.append($0) }

        let entry = try picker.inspect().find(button: Feature.presetBrowser.title)
        try? entry.tap()

        #expect(chosen.isEmpty, "an unfinished entry point must not apply a preset")
    }

    // MARK: - Selection

    @Test("Choosing a preset hands that preset to the caller")
    func selectionReportsChosenPreset() throws {
        let target = try #require(RulePresets.allPresets.first)

        nonisolated(unsafe) var chosen: [RulePreset] = []
        let picker = Self.makePicker { chosen.append($0) }

        let button = try picker.inspect().find(button: target.name)
        try button.tap()

        #expect(chosen.count == 1)
        #expect(chosen.first?.id == target.id)
    }

    @Test("Each preset reports itself, not a neighbour")
    func everyPresetReportsItsOwnIdentity() throws {
        for preset in RulePresets.allPresets {
            nonisolated(unsafe) var chosen: RulePreset?
            let picker = Self.makePicker { chosen = $0 }

            try picker.inspect().find(button: preset.name).tap()

            #expect(chosen?.id == preset.id, "\(preset.id) reported \(chosen?.id ?? "nothing")")
            #expect(chosen?.ruleIds == preset.ruleIds)
        }
    }

    @Test("The picker reports nothing until a preset is chosen")
    func reportsNothingWithoutSelection() {
        nonisolated(unsafe) var chosen: [RulePreset] = []
        _ = Self.makePicker { chosen.append($0) }

        #expect(chosen.isEmpty)
    }

    @Test("Choosing twice reports twice")
    func repeatedSelectionReportsEachTime() throws {
        let target = try #require(RulePresets.allPresets.first)

        nonisolated(unsafe) var chosen: [RulePreset] = []
        let picker = Self.makePicker { chosen.append($0) }

        try picker.inspect().find(button: target.name).tap()
        try picker.inspect().find(button: target.name).tap()

        #expect(chosen.count == 2)
    }

    // MARK: - Active preset

    @Test("With no active preset, the menu offers no way to turn one off")
    func noTurnOffWithoutActivePreset() {
        #expect(!Self.menuContains(Self.makePicker(), text: "Turn Off"))
    }

    @Test("With an active preset, the menu offers to turn it off")
    func offersTurnOffForActivePreset() throws {
        let active = try #require(RulePresets.allPresets.first)

        nonisolated(unsafe) var turnedOff = 0
        let picker = RulePresetPicker(
            activePreset: active,
            onTurnOff: { turnedOff += 1 },
            onPresetSelected: { _ in }
        )

        try picker.inspect().find(button: "Turn Off \u{201C}\(active.name)\u{201D}").tap()

        #expect(turnedOff == 1)
    }

    @Test("Choosing the active preset again turns it off instead of reapplying it")
    func choosingActivePresetTurnsItOff() throws {
        let active = try #require(RulePresets.allPresets.first)

        nonisolated(unsafe) var turnedOff = 0
        nonisolated(unsafe) var chosen: [RulePreset] = []
        let picker = RulePresetPicker(
            activePreset: active,
            onTurnOff: { turnedOff += 1 },
            onPresetSelected: { chosen.append($0) }
        )

        try picker.inspect().find(button: active.name).tap()

        #expect(turnedOff == 1)
        #expect(chosen.isEmpty)
    }

    @Test("Choosing a different preset while one is active switches to it")
    func choosingAnotherPresetSwitches() throws {
        let active = try #require(RulePresets.allPresets.first)
        let other = try #require(RulePresets.allPresets.last)
        #expect(active.id != other.id)

        nonisolated(unsafe) var turnedOff = 0
        nonisolated(unsafe) var chosen: [RulePreset] = []
        let picker = RulePresetPicker(
            activePreset: active,
            onTurnOff: { turnedOff += 1 },
            onPresetSelected: { chosen.append($0) }
        )

        try picker.inspect().find(button: other.name).tap()

        #expect(turnedOff == 0)
        #expect(chosen.map(\.id) == [other.id])
    }
}
