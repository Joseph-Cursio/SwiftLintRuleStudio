//
//  RuleBrowserViewModelTypeAndPresetTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the rule browser's Type filter (default vs opt-in), how it combines
//  with Status, and the active preset: applying, combining, and turning it off.
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleBrowserViewModelTypeAndPresetTests {

    private struct StubSwiftLintCLI: SwiftLintCLIProtocol {
        func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
        func executeRulesCommand() throws -> Data { Data() }
        func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
        func generateDocsForRule(ruleId _: String) throws -> String { "" }
        func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
        func getVersion() throws -> String { "0.0.0" }
    }

    private func makeRule(
        _ id: String,
        isOptIn: Bool,
        isEnabled: Bool,
        category: RuleCategory
    ) -> Rule {
        Rule(
            id: id,
            name: id,
            description: id,
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: isEnabled,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    /// One rule for each combination of default/opt-in and enabled/disabled.
    private func makeViewModel() -> RuleBrowserViewModel {
        let rules = [
            makeRule("default_on", isOptIn: false, isEnabled: true, category: .lint),
            makeRule("default_off", isOptIn: false, isEnabled: false, category: .style),
            makeRule("opt_in_on", isOptIn: true, isEnabled: true, category: .lint),
            makeRule("opt_in_off", isOptIn: true, isEnabled: false, category: .style)
        ]
        let registry = RuleRegistry(swiftLintCLI: StubSwiftLintCLI(), cacheManager: CacheManager.createForTesting())
        registry.setRulesForTesting(rules)
        return RuleBrowserViewModel(ruleRegistry: registry)
    }

    private let preset = RulePreset(
        id: "test_preset",
        name: "Test Preset",
        description: "Two of the four rules",
        icon: "star",
        ruleIds: ["default_off", "opt_in_off"],
        category: .codeStyle
    )

    private func shownIds(_ viewModel: RuleBrowserViewModel) -> [String] {
        viewModel.filteredRules.map(\.id).sorted()
    }

    // MARK: - Type filter

    @Test("Type: Default shows only rules SwiftLint runs out of the box")
    func testTypeDefault() {
        let viewModel = makeViewModel()
        viewModel.selectedType = .onByDefault
        #expect(shownIds(viewModel) == ["default_off", "default_on"])
    }

    @Test("Type: Opt-In shows only opt-in rules")
    func testTypeOptIn() {
        let viewModel = makeViewModel()
        viewModel.selectedType = .optIn
        #expect(shownIds(viewModel) == ["opt_in_off", "opt_in_on"])
    }

    @Test("Status and Type combine")
    func testStatusAndTypeCombine() {
        let viewModel = makeViewModel()

        viewModel.selectedStatus = .disabled
        viewModel.selectedType = .onByDefault
        #expect(shownIds(viewModel) == ["default_off"], "default rules this configuration turns off")

        viewModel.selectedStatus = .enabled
        viewModel.selectedType = .optIn
        #expect(shownIds(viewModel) == ["opt_in_on"], "opt-in rules this configuration turns on")
    }

    @Test("Category counts respect the Type filter")
    func testCategoryCountsRespectType() {
        let viewModel = makeViewModel()
        viewModel.selectedType = .optIn
        #expect(viewModel.categoryCounts[.lint] == 1)
        #expect(viewModel.categoryCounts[.style] == 1)

        viewModel.selectedStatus = .enabled
        #expect(viewModel.categoryCounts[.lint] == 1)
        #expect(viewModel.categoryCounts[.style] == nil)
    }

    @Test("Each filter's All case matches every rule")
    func testAllMatchesEverything() {
        let viewModel = makeViewModel()
        #expect(viewModel.filteredRules.count == 4)
        for rule in viewModel.filteredRules {
            #expect(RuleStatusFilter.all.matches(rule))
            #expect(RuleTypeFilter.all.matches(rule))
        }
    }

    // MARK: - Presets

    @Test("Applying a preset shows only its rules and clears the other filters")
    func testApplyPreset() {
        let viewModel = makeViewModel()
        viewModel.searchText = "default"
        viewModel.selectedStatus = .enabled
        viewModel.selectedType = .onByDefault
        viewModel.selectedCategory = .lint

        viewModel.applyPreset(preset)

        #expect(viewModel.activePreset == preset)
        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.selectedStatus == .all)
        #expect(viewModel.selectedType == .all)
        #expect(viewModel.selectedCategory == nil)
        #expect(shownIds(viewModel) == ["default_off", "opt_in_off"])
    }

    @Test("A preset stays on when another filter changes")
    func testPresetCombinesWithFilters() {
        let viewModel = makeViewModel()
        viewModel.applyPreset(preset)

        viewModel.selectedType = .optIn
        #expect(viewModel.activePreset == preset)
        #expect(shownIds(viewModel) == ["opt_in_off"], "preset and Type filter both apply")
    }

    @Test("Turning off a preset shows all rules again and keeps the other filters")
    func testTurnOffPreset() {
        let viewModel = makeViewModel()
        viewModel.applyPreset(preset)
        viewModel.selectedType = .optIn

        viewModel.turnOffPreset()

        #expect(viewModel.activePreset == nil)
        #expect(viewModel.selectedType == .optIn)
        #expect(shownIds(viewModel) == ["opt_in_off", "opt_in_on"])
    }

    @Test("Clear Filters turns off the preset and resets Type")
    func testClearFiltersClearsPresetAndType() {
        let viewModel = makeViewModel()
        viewModel.applyPreset(preset)
        viewModel.selectedType = .optIn

        viewModel.clearFilters()

        #expect(viewModel.activePreset == nil)
        #expect(viewModel.selectedType == .all)
        #expect(viewModel.filteredRules.count == 4)
    }

    @Test("Category counts respect the active preset")
    func testCategoryCountsRespectPreset() {
        let viewModel = makeViewModel()
        viewModel.applyPreset(preset)
        #expect(viewModel.categoryCounts[.style] == 2)
        #expect(viewModel.categoryCounts[.lint] == nil)
    }

    // MARK: - hasActiveFilters

    @Test("hasActiveFilters counts the Type filter and an active preset")
    func testHasActiveFilters() {
        let viewModel = makeViewModel()
        #expect(!viewModel.hasActiveFilters)

        viewModel.selectedType = .optIn
        #expect(viewModel.hasActiveFilters)

        viewModel.clearFilters()
        viewModel.applyPreset(preset)
        #expect(viewModel.hasActiveFilters, "a preset alone must enable Clear Filters")

        viewModel.turnOffPreset()
        #expect(!viewModel.hasActiveFilters)
    }
}
