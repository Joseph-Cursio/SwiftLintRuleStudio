//
//  RuleBrowserViewModel.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Combine

/// View model for the Rule Browser, managing search and filter state
@MainActor
class RuleBrowserViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet { updateFilteredRules() }
    }
    @Published var selectedCategory: RuleCategory? {
        didSet { updateFilteredRules() }
    }
    @Published var selectedStatus: RuleStatusFilter = .all {
        didSet { updateFilteredRules() }
    }
    @Published var selectedSortOption: SortOption = .name {
        didSet { updateFilteredRules() }
    }
    
    @Published var ruleRegistry: RuleRegistry {
        didSet {
            // Re-subscribe when ruleRegistry changes
            setupSubscriptions()
        }
    }
    @Published private(set) var filteredRules: [Rule] = []

    // Multi-select / bulk operations
    @Published var isMultiSelectMode: Bool = false
    @Published var selectedRuleIds: Set<String> = Set()
    @Published var bulkDiff: YAMLConfigurationEngine.ConfigDiff?
    @Published var showBulkDiffPreview: Bool = false

    private var cancellables = Set<AnyCancellable>()
    
    init(ruleRegistry: RuleRegistry) {
        self.ruleRegistry = ruleRegistry
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Cancel old subscriptions
        cancellables.removeAll()
        
        // Observe changes to ruleRegistry.rules and update filteredRules
        ruleRegistry.$rules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredRules()
            }
            .store(in: &cancellables)
        
        // Initial update
        updateFilteredRules()
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
        
        // Apply status filter
        switch selectedStatus {
        case .all:
            break // Show all rules
        case .enabled:
            // Show only rules that are explicitly enabled in config
            rules = rules.filter { $0.isEnabled }
        case .disabled:
            // Show rules that are not enabled (either disabled or not configured)
            rules = rules.filter { !$0.isEnabled }
        case .optIn:
            // Show only opt-in rules (rules that must be explicitly enabled)
            rules = rules.filter { $0.isOptIn }
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
        
        // Apply status filter if active
        switch selectedStatus {
        case .all:
            break
        case .enabled:
            rules = rules.filter { $0.isEnabled }
        case .disabled:
            rules = rules.filter { !$0.isEnabled }
        case .optIn:
            rules = rules.filter { $0.isOptIn }
        }
        
        return Dictionary(grouping: rules, by: { $0.category })
            .mapValues { $0.count }
    }
    
    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        selectedStatus = .all
        // updateFilteredRules() will be called automatically via Combine
    }

    /// Apply a rule preset by filtering to show only the preset's rules
    /// - Parameter preset: The preset to apply
    func applyPreset(_ preset: RulePreset) {
        // Clear existing filters first
        selectedCategory = nil
        selectedStatus = .all

        // Build search query from preset rule IDs
        // We join with OR-style matching by searching for preset name
        // This is a simple approach - a more sophisticated one would
        // add a dedicated preset filter
        searchText = ""

        // Filter to show only preset rules by updating directly
        let presetRuleIds = Set(preset.ruleIds)
        let allRules = ruleRegistry.rules

        filteredRules = allRules.filter { rule in
            presetRuleIds.contains(rule.id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    func ruleIsInPreset(_ rule: Rule, preset: RulePreset) -> Bool {
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

    func enableSelectedRules(yamlEngine: YAMLConfigurationEngine) {
        do {
            try yamlEngine.load()
            var config = yamlEngine.getConfig()

            for ruleId in selectedRuleIds {
                var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: true)
                ruleConfig.enabled = true
                config.rules[ruleId] = ruleConfig

                // Handle opt-in rules
                if let rule = ruleRegistry.rules.first(where: { $0.id == ruleId }), rule.isOptIn {
                    var optInRules = config.optInRules ?? []
                    if !optInRules.contains(ruleId) {
                        optInRules.append(ruleId)
                        config.optInRules = optInRules
                    }
                }

                // Remove from disabled_rules if present
                config.disabledRules?.removeAll { $0 == ruleId }
                if config.disabledRules?.isEmpty == true { config.disabledRules = nil }
            }

            bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
            showBulkDiffPreview = true
        } catch {
            print("Error generating bulk enable diff: \(error)")
        }
    }

    func disableSelectedRules(yamlEngine: YAMLConfigurationEngine) {
        do {
            try yamlEngine.load()
            var config = yamlEngine.getConfig()

            for ruleId in selectedRuleIds {
                var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: false)
                ruleConfig.enabled = false
                config.rules[ruleId] = ruleConfig

                // Remove from opt-in rules
                config.optInRules?.removeAll { $0 == ruleId }
                if config.optInRules?.isEmpty == true { config.optInRules = nil }
            }

            bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
            showBulkDiffPreview = true
        } catch {
            print("Error generating bulk disable diff: \(error)")
        }
    }

    func setSeverityForSelected(_ severity: Severity, yamlEngine: YAMLConfigurationEngine) {
        do {
            try yamlEngine.load()
            var config = yamlEngine.getConfig()

            for ruleId in selectedRuleIds {
                var ruleConfig = config.rules[ruleId] ?? RuleConfiguration(enabled: true)
                ruleConfig.severity = severity
                config.rules[ruleId] = ruleConfig
            }

            bulkDiff = yamlEngine.generateDiff(proposedConfig: config)
            showBulkDiffPreview = true
        } catch {
            print("Error generating bulk severity diff: \(error)")
        }
    }

    func saveBulkChanges(yamlEngine: YAMLConfigurationEngine) throws {
        try yamlEngine.load()
        guard let diff = bulkDiff else { return }

        // Reconstruct the proposed config by parsing the diff's after YAML
        // We rebuild from scratch since ConfigDiff stores the serialized form
        let afterContent = diff.after
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempConfig = tempDir.appendingPathComponent(".swiftlint.yml")
        try afterContent.write(to: tempConfig, atomically: true, encoding: .utf8)

        let tempEngine = YAMLConfigurationEngine(configPath: tempConfig)
        try tempEngine.load()
        let proposedConfig = tempEngine.getConfig()

        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDir)

        try yamlEngine.save(config: proposedConfig, createBackup: true)
        bulkDiff = nil

        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["bulkChange": true]
        )
    }
}

/// Filter options for rule status
enum RuleStatusFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled
    case optIn
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .optIn: return "Opt-In"
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
