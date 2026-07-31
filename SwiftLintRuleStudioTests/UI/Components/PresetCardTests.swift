//
//  PresetCardTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the preset card used by the staged preset browser.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite("PresetCard")
struct PresetCardTests {

    private static func makeCard(
        preset: RulePreset = RulePresets.performance,
        isHovered: Bool = false
    ) -> PresetCard {
        PresetCard(preset: preset, isHovered: isHovered)
    }

    private static func cardContains(_ card: PresetCard, text: String) -> Bool {
        (try? card.inspect().find(text: text)) != nil
    }

    // MARK: - Contents

    @Test("The card shows the preset's name, category and description")
    func showsPresetIdentity() {
        let preset = RulePresets.performance
        let card = Self.makeCard(preset: preset)

        #expect(Self.cardContains(card, text: preset.name))
        #expect(Self.cardContains(card, text: preset.category.displayName))
        #expect(Self.cardContains(card, text: preset.description))
    }

    @Test("The card counts the preset's rules")
    func showsRuleCount() {
        let preset = RulePresets.performance
        let card = Self.makeCard(preset: preset)

        #expect(Self.cardContains(card, text: "\(preset.ruleIds.count) rules"))
    }

    @Test("Every catalogue preset renders")
    func rendersEveryPreset() {
        for preset in RulePresets.allPresets {
            let card = Self.makeCard(preset: preset)

            #expect(Self.cardContains(card, text: preset.name), "\(preset.id) did not render")
        }
    }

    // MARK: - Category colour

    @Test("Each category has its own accent colour")
    func categoryColoursAreDistinct() {
        let colors = RulePreset.PresetCategory.allCases.map(PresetCard.color(for:))

        #expect(Set(colors.map(String.init(describing:))).count == colors.count)
    }

    @Test("Category colours are stable")
    func categoryColoursAreStable() {
        #expect(PresetCard.color(for: .performance) == .orange)
        #expect(PresetCard.color(for: .swiftUI) == .blue)
        #expect(PresetCard.color(for: .concurrency) == .purple)
        #expect(PresetCard.color(for: .codeStyle) == .green)
        #expect(PresetCard.color(for: .documentation) == .cyan)
    }
}
