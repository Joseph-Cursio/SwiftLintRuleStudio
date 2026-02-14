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

    @Test("Performance preset has valid rule IDs")
    func testPerformancePreset() {
        let preset = RulePresets.performance

        #expect(preset.id == "performance")
        #expect(preset.name == "Performance")
        #expect(preset.category == .performance)
        #expect(!preset.ruleIds.isEmpty)
        #expect(preset.ruleIds.contains("reduce_into"))
        #expect(preset.ruleIds.contains("first_where"))
        #expect(preset.ruleIds.contains("empty_count"))
    }

    @Test("SwiftUI preset has valid rule IDs")
    func testSwiftUIPreset() {
        let preset = RulePresets.swiftUI

        #expect(preset.id == "swiftui")
        #expect(preset.name == "SwiftUI")
        #expect(preset.category == .swiftUI)
        #expect(!preset.ruleIds.isEmpty)
        #expect(preset.ruleIds.contains("attributes"))
        #expect(preset.ruleIds.contains("modifier_order"))
    }

    @Test("Concurrency Safety preset has valid rule IDs")
    func testConcurrencySafetyPreset() {
        let preset = RulePresets.concurrencySafety

        #expect(preset.id == "concurrency_safety")
        #expect(preset.name == "Concurrency Safety")
        #expect(preset.category == .concurrency)
        #expect(!preset.ruleIds.isEmpty)
        #expect(preset.ruleIds.contains("unavailable_from_async"))
    }

    @Test("Code Style preset has valid rule IDs")
    func testCodeStylePreset() {
        let preset = RulePresets.codeStyle

        #expect(preset.id == "code_style")
        #expect(preset.name == "Code Style")
        #expect(preset.category == .codeStyle)
        #expect(!preset.ruleIds.isEmpty)
        #expect(preset.ruleIds.contains("opening_brace"))
        #expect(preset.ruleIds.contains("closing_brace"))
        #expect(preset.ruleIds.contains("comma"))
    }

    @Test("Documentation preset has valid rule IDs")
    func testDocumentationPreset() {
        let preset = RulePresets.documentation

        #expect(preset.id == "documentation")
        #expect(preset.name == "Documentation")
        #expect(preset.category == .documentation)
        #expect(!preset.ruleIds.isEmpty)
        #expect(preset.ruleIds.contains("missing_docs"))
    }

    // MARK: - Lookup Tests

    @Test("Can lookup preset by ID")
    func testPresetLookupById() {
        let performance = RulePresets.preset(for: "performance")
        #expect(performance != nil)
        #expect(performance?.name == "Performance")

        let swiftui = RulePresets.preset(for: "swiftui")
        #expect(swiftui != nil)
        #expect(swiftui?.name == "SwiftUI")

        let unknown = RulePresets.preset(for: "nonexistent")
        #expect(unknown == nil)
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
        #expect(!performanceRules.isEmpty)
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
        #expect(!RulePreset.PresetCategory.performance.icon.isEmpty)
        #expect(!RulePreset.PresetCategory.swiftUI.icon.isEmpty)
        #expect(!RulePreset.PresetCategory.concurrency.icon.isEmpty)
        #expect(!RulePreset.PresetCategory.codeStyle.icon.isEmpty)
        #expect(!RulePreset.PresetCategory.documentation.icon.isEmpty)
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
            #expect(!preset.description.isEmpty, "Preset \(preset.id) has empty description")
        }
    }

    @Test("All presets have valid SF Symbol icons")
    func testPresetsHaveValidIcons() {
        for preset in RulePresets.allPresets {
            #expect(!preset.icon.isEmpty, "Preset \(preset.id) has empty icon")
        }
    }

    @Test("All presets have at least one rule")
    func testPresetsHaveRules() {
        for preset in RulePresets.allPresets {
            #expect(!preset.ruleIds.isEmpty, "Preset \(preset.id) has no rules")
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
