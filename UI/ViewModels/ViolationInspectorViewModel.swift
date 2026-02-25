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

    // Table column sort order (used by SwiftUI Table in non-grouped mode)
    @Published var tableSortOrder: [KeyPathComparator<Violation>] = []
    
    // MARK: - Properties
    
    var violationStorage: ViolationStorageProtocol
    var workspaceAnalyzer: WorkspaceAnalyzer?
    var cancellables = Set<AnyCancellable>()
    var workspaceId: UUID?
    var currentWorkspace: Workspace?
    var isInitialized = false
    var isUpdatingSelection = false
    
    // MARK: - Initialization
    
    init(violationStorage: ViolationStorageProtocol, workspaceAnalyzer: WorkspaceAnalyzer? = nil) {
        self.violationStorage = violationStorage
        self.workspaceAnalyzer = workspaceAnalyzer
        // Mark as initialized after all properties are set
        // This prevents didSet observers from running during initialization
        self.isInitialized = true
    }
    
}
