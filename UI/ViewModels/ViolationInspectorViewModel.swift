//
//  ViolationInspectorViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for managing violation inspection state
//

import Foundation
import Combine

@MainActor
class ViolationInspectorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var violations: [Violation] = []
    @Published var filteredViolations: [Violation] = []
    @Published var selectedViolationId: UUID? {
        didSet { syncSelectionFromSingle() }
    }
    @Published var selectedViolationIds: Set<UUID> = [] {
        didSet { syncSelectionFromSet() }
    }
    @Published var isAnalyzing: Bool = false
    
    // Filter properties
    @Published var searchText: String = "" {
        didSet { updateFilteredViolations() }
    }
    @Published var selectedRuleIDs: Set<String> = [] {
        didSet { updateFilteredViolations() }
    }
    @Published var selectedSeverities: Set<Severity> = [] {
        didSet { updateFilteredViolations() }
    }
    @Published var selectedFiles: Set<String> = [] {
        didSet { updateFilteredViolations() }
    }
    @Published var showSuppressedOnly: Bool = false {
        didSet { updateFilteredViolations() }
    }
    
    // Grouping and sorting
    @Published var groupingOption: ViolationGroupingOption = .none {
        didSet { updateFilteredViolations() }
    }
    @Published var sortOption: ViolationSortOption = .file {
        didSet { updateFilteredViolations() }
    }
    @Published var sortOrder: ViolationSortOrder = .ascending {
        didSet { updateFilteredViolations() }
    }
    
    // MARK: - Computed Properties
    
    var selectedViolation: Violation? {
        guard let selectedId = selectedViolationId else { return nil }
        return violations.first { $0.id == selectedId }
    }
    
    var violationCount: Int {
        filteredViolations.count
    }
    
    var errorCount: Int {
        filteredViolations.filter { $0.severity == .error }.count
    }
    
    var warningCount: Int {
        filteredViolations.filter { $0.severity == .warning }.count
    }
    
    var uniqueRules: [String] {
        Array(Set(violations.map { $0.ruleID })).sorted()
    }
    
    var uniqueFiles: [String] {
        Array(Set(violations.map { $0.filePath })).sorted()
    }
    
    // MARK: - Properties
    
    var violationStorage: ViolationStorageProtocol
    var workspaceAnalyzer: WorkspaceAnalyzer?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceId: UUID?
    private var currentWorkspace: Workspace?
    private var isInitialized = false
    private var isUpdatingSelection = false
    
    // MARK: - Initialization
    
    init(violationStorage: ViolationStorageProtocol, workspaceAnalyzer: WorkspaceAnalyzer? = nil) {
        self.violationStorage = violationStorage
        self.workspaceAnalyzer = workspaceAnalyzer
        // Mark as initialized after all properties are set
        // This prevents didSet observers from running during initialization
        self.isInitialized = true
    }
    
    // MARK: - Public Methods
    
    func loadViolations(for workspaceId: UUID, workspace: Workspace? = nil) async throws {
        self.workspaceId = workspaceId
        if let workspace = workspace {
            self.currentWorkspace = workspace
        }
        
        // First, try to run analysis to detect violations
        if let workspace = workspace ?? currentWorkspace,
           let analyzer = workspaceAnalyzer {
            // Subscribe to analyzer state changes
            analyzer.$isAnalyzing
                .receive(on: DispatchQueue.main)
                .sink { [weak self] analyzing in
                    self?.isAnalyzing = analyzing
                }
                .store(in: &cancellables)
            
            do {
                _ = try await analyzer.analyze(workspace: workspace, configPath: workspace.configPath)
            } catch {
                print("❌ Error analyzing workspace: \(error.localizedDescription)")
                // Continue to load existing violations even if analysis fails
            }
        }
        
        // Load violations from storage
        let filter = ViolationFilter()
        let fetched = try await violationStorage.fetchViolations(
            filter: filter,
            workspaceId: workspaceId
        )
        
        violations = fetched
        updateFilteredViolations()
    }
    
    func refreshViolations() async throws {
        guard let workspaceId = workspaceId,
              let workspace = currentWorkspace,
              let analyzer = workspaceAnalyzer else {
            // Fallback: just reload from storage if we don't have analyzer
            guard let workspaceId = workspaceId else { return }
            let filter = ViolationFilter()
            let fetched = try await violationStorage.fetchViolations(
                filter: filter,
                workspaceId: workspaceId
            )
            violations = fetched
            updateFilteredViolations()
            return
        }
        
        // Run analysis to detect new violations
        do {
            _ = try await analyzer.analyze(workspace: workspace, configPath: workspace.configPath)
        } catch {
            print("Error analyzing workspace: \(error)")
            throw error
        }
        
        // Reload violations from storage
        try await loadViolations(for: workspaceId, workspace: workspace)
    }
    
    func clearViolations() {
        violations = []
        filteredViolations = []
        workspaceId = nil
        selectedViolationId = nil
        selectedViolationIds.removeAll()
    }
    
    func selectNextViolation() {
        guard !filteredViolations.isEmpty else { return }
        if let currentId = selectedViolationId,
           let currentIndex = filteredViolations.firstIndex(where: { $0.id == currentId }),
           currentIndex < filteredViolations.count - 1 {
            setPrimarySelection(filteredViolations[currentIndex + 1].id)
        } else if selectedViolationId == nil {
            setPrimarySelection(filteredViolations.first?.id)
        }
    }
    
    func selectPreviousViolation() {
        guard !filteredViolations.isEmpty else { return }
        if let currentId = selectedViolationId,
           let currentIndex = filteredViolations.firstIndex(where: { $0.id == currentId }),
           currentIndex > 0 {
            setPrimarySelection(filteredViolations[currentIndex - 1].id)
        } else if selectedViolationId == nil {
            setPrimarySelection(filteredViolations.last?.id)
        }
    }
    
    func selectAll() {
        selectedViolationIds = Set(filteredViolations.map { $0.id })
    }
    
    func deselectAll() {
        selectedViolationIds.removeAll()
    }
    
    func suppressSelectedViolations(reason: String) async throws {
        guard workspaceId != nil else { return }
        let ids = Array(selectedViolationIds)
        try await violationStorage.suppressViolations(ids, reason: reason)
        try await refreshViolations()
        selectedViolationIds.removeAll()
    }
    
    func resolveSelectedViolations() async throws {
        guard workspaceId != nil else { return }
        let ids = Array(selectedViolationIds)
        try await violationStorage.resolveViolations(ids)
        try await refreshViolations()
        selectedViolationIds.removeAll()
    }
    
    func clearFilters() {
        searchText = ""
        selectedRuleIDs.removeAll()
        selectedSeverities.removeAll()
        selectedFiles.removeAll()
        showSuppressedOnly = false
    }
    
    // MARK: - Private Methods
    
    private func updateFilteredViolations() {
        // Don't update if not yet initialized (prevents crashes during init)
        guard isInitialized else { return }
        
        var filtered = violations
        
        // Apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter { violation in
                violation.ruleID.lowercased().contains(searchLower) ||
                violation.message.lowercased().contains(searchLower) ||
                violation.filePath.lowercased().contains(searchLower)
            }
        }
        
        // Apply rule filter
        if !selectedRuleIDs.isEmpty {
            filtered = filtered.filter { selectedRuleIDs.contains($0.ruleID) }
        }
        
        // Apply severity filter
        if !selectedSeverities.isEmpty {
            filtered = filtered.filter { selectedSeverities.contains($0.severity) }
        }
        
        // Apply file filter
        if !selectedFiles.isEmpty {
            filtered = filtered.filter { selectedFiles.contains($0.filePath) }
        }
        
        // Apply suppressed filter
        if showSuppressedOnly {
            filtered = filtered.filter { $0.suppressed }
        }
        
        // Apply sorting
        filtered = sortViolations(filtered)
        
        // Grouping is handled in the view layer, not here
        // We keep filteredViolations flat for now
        filteredViolations = filtered
        updateSelectionForFilteredViolations(filtered)
    }
    
    private func sortViolations(_ violations: [Violation]) -> [Violation] {
        let sorted = violations.sorted { lhs, rhs in
            let comparison: ComparisonResult
            
            switch sortOption {
            case .file:
                comparison = lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath)
                if comparison == .orderedSame {
                    return lhs.line < rhs.line
                }
            case .rule:
                comparison = lhs.ruleID.localizedCaseInsensitiveCompare(rhs.ruleID)
                if comparison == .orderedSame {
                    return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
                }
            case .severity:
                if lhs.severity != rhs.severity {
                    return lhs.severity == .error && rhs.severity == .warning
                }
                return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
            case .date:
                return lhs.detectedAt > rhs.detectedAt
            case .line:
                if lhs.filePath != rhs.filePath {
                    return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
                }
                return lhs.line < rhs.line
            }
            
            return sortOrder == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        
        return sorted
    }

    private func syncSelectionFromSet() {
        guard isInitialized, !isUpdatingSelection else { return }
        isUpdatingSelection = true

        if selectedViolationIds.isEmpty {
            selectedViolationId = nil
        } else if let currentId = selectedViolationId, selectedViolationIds.contains(currentId) {
            // Keep current selection
        } else {
            selectedViolationId = filteredViolations.first { selectedViolationIds.contains($0.id) }?.id
        }

        isUpdatingSelection = false
    }

    private func syncSelectionFromSingle() {
        guard isInitialized, !isUpdatingSelection else { return }
        isUpdatingSelection = true

        if let selectedViolationId {
            selectedViolationIds = [selectedViolationId]
        } else {
            selectedViolationIds.removeAll()
        }

        isUpdatingSelection = false
    }

    private func updateSelectionForFilteredViolations(_ filtered: [Violation]) {
        guard isInitialized, !isUpdatingSelection else { return }
        let filteredIds = Set(filtered.map { $0.id })
        let hasInvalidSelection = !selectedViolationIds.isSubset(of: filteredIds)
            || (selectedViolationId != nil && !filteredIds.contains(selectedViolationId!))

        guard hasInvalidSelection else { return }

        isUpdatingSelection = true
        selectedViolationIds = selectedViolationIds.intersection(filteredIds)

        if let currentSelectedId = selectedViolationId, !selectedViolationIds.contains(currentSelectedId) {
            selectedViolationId = selectedViolationIds.isEmpty
                ? nil
                : filtered.first { selectedViolationIds.contains($0.id) }?.id
        } else if selectedViolationId == nil {
            selectedViolationId = filtered.first { selectedViolationIds.contains($0.id) }?.id
        }

        isUpdatingSelection = false
    }

    private func setPrimarySelection(_ id: UUID?) {
        guard isInitialized else { return }
        isUpdatingSelection = true
        selectedViolationId = id
        selectedViolationIds = id.map { [$0] } ?? []
        isUpdatingSelection = false
    }
}

// MARK: - Grouping Options

enum ViolationGroupingOption: String, CaseIterable {
    case none = "None"
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
}

// MARK: - Sort Options

enum ViolationSortOption: String, CaseIterable {
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
    case date = "Date"
    case line = "Line"
}

enum ViolationSortOrder: String, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
}
