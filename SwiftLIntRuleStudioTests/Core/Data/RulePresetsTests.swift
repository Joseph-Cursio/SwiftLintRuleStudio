//
//  RulePresetsTests.swift
//  SwiftLintRuleStudioTests
//
//  Unit tests for RulePresets
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct RulePresetsTests {
    // MARK: - Preset Existence Tests

    @Test("All presets exist and have unique IDs")
    func testAllPresetsExist() {
        let allPresets = RulePresets.allPresets

        #expect(allPresets.count == 5)
        #expect(allPresets.contains { $0.id == "performance" })
        #expect(allPresets.contains { $0.id == "swiftui" })
        #expect(allPresets.contains { $0.id == "concurrency_safety" })
        #expect(allPresets.contains { $0.id == "code_style" })
        #expect(allPresets.contains { $0.id == "documentation" })

        // Verify unique IDs
        let ids = Set(allPresets.map(\.id))
        #expect(ids.count == allPresets.count)
    }

    struct PresetExpectation: CustomTestStringConvertible, Sendable {
        let presetId: String
        let expectedName: String
        let expectedCategory: RulePreset.PresetCategory
        let expectedRuleIds: [String]

        var testDescription: String { presetId }

        static let all: [PresetExpectation] = [
            PresetExpectation(
                presetId: "performance", expectedName: "Performance",
                expectedCategory: .performance,
                expectedRuleIds: ["reduce_into", "first_where", "empty_count"]
            ),
            PresetExpectation(
                presetId: "swiftui", expectedName: "SwiftUI",
                expectedCategory: .swiftUI,
                expectedRuleIds: ["attributes", "modifier_order"]
            ),
            PresetExpectation(
                presetId: "concurrency_safety", expectedName: "Concurrency Safety",
                expectedCategory: .concurrency,
                expectedRuleIds: ["unavailable_from_async"]
            ),
            PresetExpectation(
                presetId: "code_style", expectedName: "Code Style",
                expectedCategory: .codeStyle,
                expectedRuleIds: ["opening_brace", "closing_brace", "comma"]
            ),
            PresetExpectation(
                presetId: "documentation", expectedName: "Documentation",
                expectedCategory: .documentation,
                expectedRuleIds: ["missing_docs"]
            )
        ]
    }

    @Test("Each preset has correct metadata and expected rule IDs", arguments: PresetExpectation.all)
    func testPresetMetadataAndRules(_ expectation: PresetExpectation) throws {
        let preset = try #require(
            RulePresets.allPresets.first { $0.id == expectation.presetId },
            "Preset \(expectation.presetId) not found"
        )

        #expect(preset.name == expectation.expectedName)
        #expect(preset.category == expectation.expectedCategory)
        #expect(reset.ruleIds.isEmpty == false)
        for ruleId in expectation.expectedRuleIds {
            #expect(preset.ruleIds.contains(ruleId), "\(expectation.presetId) preset should contain \(ruleId)")
        }
    }

    // MARK: - Lookup Tests

    @Test("Can lookup preset by ID")
    func testPresetLookupById() throws {
        let performance = try #require(RulePresets.preset(for: "performance"))
        #expect(performance.name == "Performance")

        let swiftui = try #require(RulePresets.preset(for: "swiftui"))
        #expect(swiftui.name == "SwiftUI")

        #expect(RulePresets.preset(for: "nonexistent") == nil)
    }

    @Test("Can get presets by category")
    func testPresetsByCategory() {
        let performancePresets = RulePresets.presets(in: .performance)
        #expect(performancePresets.count == 1)
        #expect(performancePresets.first?.id == "performance")

        let swiftUIPresets = RulePresets.presets(in: .swiftUI)
        #expect(swiftUIPresets.count == 1)
        #expect(swiftUIPresets.first?.id == "swiftui")
    }

    @Test("Can get rule IDs for preset")
    func testRuleIdsForPreset() {
        let performanceRules = RulePresets.ruleIds(for: "performance")
        #expect(erformanceRules.isEmpty == false)
        #expect(performanceRules.contains("reduce_into"))

        let unknownRules = RulePresets.ruleIds(for: "nonexistent")
        #expect(unknownRules.isEmpty)
    }

    // MARK: - Category Tests

    @Test("All preset categories have display names")
    func testPresetCategoryDisplayNames() {
        #expect(RulePreset.PresetCategory.performance.displayName == "Performance")
        #expect(RulePreset.PresetCategory.swiftUI.displayName == "SwiftUI")
        #expect(RulePreset.PresetCategory.concurrency.displayName == "Concurrency")
        #expect(RulePreset.PresetCategory.codeStyle.displayName == "Code Style")
        #expect(RulePreset.PresetCategory.documentation.displayName == "Documentation")
    }

    @Test("All preset categories have icons")
    func testPresetCategoryIcons() {
        #expect(ulePreset.PresetCategory.performance.icon.isEmpty == false)
        #expect(ulePreset.PresetCategory.swiftUI.icon.isEmpty == false)
        #expect(ulePreset.PresetCategory.concurrency.icon.isEmpty == false)
        #expect(ulePreset.PresetCategory.codeStyle.icon.isEmpty == false)
        #expect(ulePreset.PresetCategory.documentation.icon.isEmpty == false)
    }

    // MARK: - Codable Tests

    @Test("RulePreset is encodable and decodable")
    func testPresetCodable() throws {
        let preset = RulePresets.performance
        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RulePreset.self, from: data)

        #expect(decoded.id == preset.id)
        #expect(decoded.name == preset.name)
        #expect(decoded.description == preset.description)
        #expect(decoded.icon == preset.icon)
        #expect(decoded.ruleIds == preset.ruleIds)
        #expect(decoded.category == preset.category)
    }

    // MARK: - Validation Tests

    @Test("All presets have non-empty descriptions")
    func testPresetsHaveDescriptions() {
        for preset in RulePresets.allPresets {
            #expect(reset.description.isEmpty, "Preset \(preset.id) has empty description" == false)
        }
    }

    @Test("All presets have valid SF Symbol icons")
    func testPresetsHaveValidIcons() {
        for preset in RulePresets.allPresets {
            #expect(reset.icon.isEmpty, "Preset \(preset.id) has empty icon" == false)
        }
    }

    @Test("All presets have at least one rule")
    func testPresetsHaveRules() {
        for preset in RulePresets.allPresets {
            #expect(reset.ruleIds.isEmpty, "Preset \(preset.id) has no rules" == false)
        }
    }

    @Test("No duplicate rule IDs within presets")
    func testNoDuplicateRulesInPresets() {
        for preset in RulePresets.allPresets {
            let uniqueIds = Set(preset.ruleIds)
            #expect(
                uniqueIds.count == preset.ruleIds.count,
                "Preset \(preset.id) has duplicate rule IDs"
            )
        }
    }
}
