//
//  RuleBrowserViewModel.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

/// Filter on whether a rule is on in this workspace's configuration.
///
/// Independent of `RuleTypeFilter`, so the two combine: "Disabled" with
/// "Default" lists the default rules this configuration turns off.
enum RuleStatusFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        }
    }

    func matches(_ rule: Rule) -> Bool {
        switch self {
        case .all: true
        case .enabled: rule.isEnabled
        // Not enabled, whether disabled explicitly or never configured.
        case .disabled: !rule.isEnabled
        }
    }
}

/// Sort options for rules
enum SortOption: String, CaseIterable, Identifiable {
    case name
    case identifier
    case category

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .identifier: return "Identifier"
        case .category: return "Category"
        }
    }
}

/// View model for the Rule Browser, managing search and filter state
@MainActor
@Observable
class RuleBrowserViewModel {
    var searchText: String = "" {
        didSet { updateFilteredRules() }
    }
    var selectedCategory: RuleCategory? {
        didSet { updateFilteredRules() }
    }
    var selectedStatus: RuleStatusFilter = .all {
        didSet { updateFilteredRules() }
    }
    var selectedType: RuleTypeFilter = .all {
        didSet { updateFilteredRules() }
    }
    /// The preset narrowing the list, if any. It combines with the other filters
    /// and stays on until turned off or cleared.
    private(set) var activePreset: RulePreset? {
        didSet { updateFilteredRules() }
    }
    var selectedSortOption: SortOption = .name {
        didSet { updateFilteredRules() }
    }

    var ruleRegistry: RuleRegistry {
        didSet { observeRulesChanges() }
    }
    private(set) var filteredRules: [Rule] = []

    // Multi-select / bulk operations
    var isMultiSelectMode: Bool = false
    var selectedRuleIds: Set<String> = Set()
    var bulkDiff: YAMLConfigurationEngine.ConfigDiff?
    /// User-facing message when a bulk operation can't proceed (e.g. the
    /// `.swiftlint.yml` failed to load). `nil` when the last operation was clean.
    var bulkOperationError: String?

    init(ruleRegistry: RuleRegistry) {
        self.ruleRegistry = ruleRegistry
        updateFilteredRules()
        observeRulesChanges()
    }

    private func observeRulesChanges() {
        withObservationTracking {
            _ = ruleRegistry.rules
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateFilteredRules()
                self?.observeRulesChanges()
            }
        }
    }

    private func updateFilteredRules() {
        let allRules = ruleRegistry.rules
        var rules = allRules

        // Apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespaces)
            rules = rules.filter { rule in
                // Search in identifier (most reliable)
                rule.id.lowercased().contains(searchLower) ||
                // Search in name
                rule.name.lowercased().contains(searchLower) ||
                // Search in description (only if not "Loading...")
                (rule.description.lowercased() != "loading..." && rule.description.lowercased().contains(searchLower))
            }
        }

        // Apply category filter
        if let category = selectedCategory {
            rules = rules.filter { $0.category == category }
        }

        // Apply status and type filters
        rules = rules.filter { selectedStatus.matches($0) && selectedType.matches($0) }

        // Apply preset filter
        if let activePreset {
            let presetRuleIds = Set(activePreset.ruleIds)
            rules = rules.filter { presetRuleIds.contains($0.id) }
        }

        // Apply sorting
        switch selectedSortOption {
        case .name:
            rules.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .identifier:
            rules.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        case .category:
            rules.sort { first, second in
                // Sort by category first, then by name within category
                if first.category.rawValue != second.category.rawValue {
                    return first.category.rawValue < second.category.rawValue
                }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
        }

        filteredRules = rules
    }

    var categoryCounts: [RuleCategory: Int] {
        // Count rules in each category, respecting current filters (except category filter)
        var rules = ruleRegistry.rules

        // Apply search filter if active
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespaces)
            rules = rules.filter { rule in
                rule.id.lowercased().contains(searchLower) ||
                rule.name.lowercased().contains(searchLower) ||
                (rule.description.lowercased() != "loading..." && rule.description.lowercased().contains(searchLower))
            }
        }

        // Apply status and type filters
        rules = rules.filter { selectedStatus.matches($0) && selectedType.matches($0) }

        // Apply preset filter if active
        if let activePreset {
            let presetRuleIds = Set(activePreset.ruleIds)
            rules = rules.filter { presetRuleIds.contains($0.id) }
        }

        return Dictionary(grouping: rules) { $0.category }
            .mapValues { $0.count }
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        selectedStatus = .all
        selectedType = .all
        activePreset = nil
        // updateFilteredRules() will be called automatically via Combine
    }

    /// Whether any filter, or a preset, is narrowing the list.
    var hasActiveFilters: Bool {
        !searchText.isEmpty
            || selectedCategory != nil
            || selectedStatus != .all
            || selectedType != .all
            || activePreset != nil
    }

    /// Show only a preset's rules. Clears the other filters first so the whole
    /// preset is visible; they can then narrow it further.
    /// - Parameter preset: The preset to apply
    func applyPreset(_ preset: RulePreset) {
        searchText = ""
        selectedCategory = nil
        selectedStatus = .all
        selectedType = .all
        activePreset = preset
    }

    /// Stop filtering by preset, leaving the other filters as they are.
    func turnOffPreset() {
        activePreset = nil
    }

    /// Get rules matching a specific preset
    /// - Parameter preset: The preset to get rules for
    /// - Returns: Array of rules matching the preset's rule IDs
    func rules(for preset: RulePreset) -> [Rule] {
        let presetRuleIds = Set(preset.ruleIds)
        return ruleRegistry.rules.filter { presetRuleIds.contains($0.id) }
    }

    /// Check if a rule belongs to a specific preset
    /// - Parameters:
    ///   - rule: The rule to check
    ///   - preset: The preset to check against
    /// - Returns: True if the rule is in the preset
    private func ruleIsInPreset(_ rule: Rule, preset: RulePreset) -> Bool {
        preset.ruleIds.contains(rule.id)
    }

    // MARK: - Multi-Select Operations

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedRuleIds.removeAll()
            bulkDiff = nil
        }
    }

    func toggleRuleSelection(_ ruleId: String) {
        if selectedRuleIds.contains(ruleId) {
            selectedRuleIds.remove(ruleId)
        } else {
            selectedRuleIds.insert(ruleId)
        }
    }

    func selectAllFiltered() {
        selectedRuleIds = Set(filteredRules.map(\.id))
    }

    func clearSelection() {
        selectedRuleIds.removeAll()
    }

    // MARK: - Bulk Operations

    /// Loads the config for a bulk operation. On success clears `bulkOperationError`
    /// and returns true; on failure records a user-facing message and returns false
    /// so the caller aborts instead of silently doing nothing.
    private func loadConfig(_ yamlEngine: any YAMLConfigurationEngineProtocol) -> Bool {
        do {
            try yamlEngine.load()
            bulkOperationError = nil
            return true
        } catch {
            bulkOperationError = "Couldn't read the SwiftLint configuration. \(error.localizedDescription)"
            return false
        }
    }

    func enableSelectedRules(yamlEngine: any YAMLConfigurationEngineProtocol) {
        guard loadConfig(yamlEngine), var config = configAcceptedBySwiftLint(yamlEngine) else { return }

        for ruleId in selectedRuleIds.sorted() {
            var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: true)
            ruleConfig.enabled = true
            config.rules[ruleId] = ruleConfig
            // only_rules when the file has one, otherwise opt_in_rules / analyzer_rules.
            // This used to ignore only_rules: an opt-in rule went into opt_in_rules beside
            // it, which SwiftLint rejects (issue #83), and a default rule went nowhere.
            config.enableRule(ruleId, kind: ruleListKind(of: ruleId))
        }

        bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
    }

    func disableSelectedRules(yamlEngine: any YAMLConfigurationEngineProtocol) {
        guard loadConfig(yamlEngine), var config = configAcceptedBySwiftLint(yamlEngine) else { return }
        let ruleIds = selectedRuleIds.sorted()

        // The whole selection at once: under only_rules, turning off every listed rule
        // would empty the list, which SwiftLint reads as "run the default rules". Rule by
        // rule, that would trip partway through and leave the earlier ones half-done.
        do {
            try config.disableRules(ruleIds, kind: ruleListKind(of:))
        } catch {
            bulkOperationError = error.localizedDescription
            return
        }
        for ruleId in ruleIds {
            var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: false)
            ruleConfig.enabled = false
            config.rules[ruleId] = ruleConfig
        }

        bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
    }

    /// The loaded configuration, or nil after recording why it can't be edited: SwiftLint
    /// rejects a file with `only_rules` beside `opt_in_rules` or `disabled_rules`, and
    /// saving one is refused. Checked before the preview rather than after the user has
    /// approved it.
    private func configAcceptedBySwiftLint(
        _ yamlEngine: any YAMLConfigurationEngineProtocol
    ) -> YAMLConfigurationEngine.YAMLConfig? {
        let config = yamlEngine.getConfig()
        guard !config.hasOnlyRulesConflict else {
            bulkOperationError = YAMLConfigError.onlyRulesConflict.localizedDescription
            return nil
        }
        return config
    }

    /// Which list turns `ruleId` on. A rule missing from the registry is treated as a
    /// default rule, so disabling it still takes effect.
    private func ruleListKind(of ruleId: String) -> RuleListKind {
        ruleRegistry.rules.first { $0.id == ruleId }.map(RuleListKind.init) ?? .standard
    }

    func setSeverityForSelected(_ severity: Severity, yamlEngine: any YAMLConfigurationEngineProtocol) {
        guard loadConfig(yamlEngine), var config = configAcceptedBySwiftLint(yamlEngine) else { return }

        for ruleId in selectedRuleIds {
            var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: true)
            ruleConfig.severity = severity
            config.rules[ruleId] = ruleConfig
        }

        bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
    }

    /// Toggle a single rule's enabled/disabled state and show a diff preview.
    func toggleRule(_ rule: Rule, yamlEngine: any YAMLConfigurationEngineProtocol) {
        // Temporarily select just this rule and reuse the existing bulk machinery.
        let previousSelection = selectedRuleIds
        selectedRuleIds = [rule.id]
        if rule.isEnabled {
            disableSelectedRules(yamlEngine: yamlEngine)
        } else {
            enableSelectedRules(yamlEngine: yamlEngine)
        }
        selectedRuleIds = previousSelection
    }

    func saveBulkChanges(yamlEngine: any YAMLConfigurationEngineProtocol) throws {
        try yamlEngine.load()
        guard let diff = bulkDiff else { return }

        // Reconstruct the proposed config by parsing the diff's after YAML
        // We rebuild from scratch since ConfigDiff stores the serialized form
        // `ConfigDiff` stores the serialized form, so the proposed config is rebuilt by
        // parsing it. That used to mean a temporary directory, a write and a read back.
        let proposedConfig = try YAMLConfigurationEngine.parse(diff.after)

        try yamlEngine.save(config: proposedConfig, createBackup: true)
        bulkDiff = nil

        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["bulkChange": true]
        )
    }
}
