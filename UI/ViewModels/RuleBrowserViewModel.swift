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
    @Published private(set) var groupedRules: [(category: RuleCategory, rules: [Rule])] = []
    
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
        
        let grouped = Dictionary(grouping: rules, by: { $0.category })
        groupedRules = grouped.map { (category, rules) in
            return (category: category, rules: rules)
        }.sorted { $0.category.displayName < $1.category.displayName }
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
