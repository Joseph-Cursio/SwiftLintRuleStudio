//
//  ViolationInspectorViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for managing violation inspection state
//

import Foundation
import Combine
import Observation

@MainActor
@Observable
class ViolationInspectorViewModel {

    // MARK: - Properties

    var violations: [Violation] = []
    var filteredViolations: [Violation] = []
    var selectedViolationId: UUID? {
        didSet { syncSelectionFromSingle() }
    }
    var selectedViolationIds: Set<UUID> = [] {
        didSet { syncSelectionFromSet() }
    }
    var isAnalyzing: Bool = false

    // Filter properties
    var searchText: String = "" {
        didSet { updateFilteredViolations() }
    }
    var selectedRuleIDs: Set<String> = [] {
        didSet { updateFilteredViolations() }
    }
    var selectedSeverities: Set<Severity> = [] {
        didSet { updateFilteredViolations() }
    }
    var selectedFiles: Set<String> = [] {
        didSet { updateFilteredViolations() }
    }
    var showSuppressedOnly: Bool = false {
        didSet { updateFilteredViolations() }
    }

    // Grouping and sorting
    var groupingOption: ViolationGroupingOption = .none {
        didSet { updateFilteredViolations() }
    }
    var sortOption: ViolationSortOption = .file {
        didSet { updateFilteredViolations() }
    }
    var sortOrder: ViolationSortOrder = .ascending {
        didSet { updateFilteredViolations() }
    }

    // Table column sort order (used by SwiftUI Table in non-grouped mode)
    var tableSortOrder: [KeyPathComparator<Violation>] = []

    // MARK: - Non-observed properties

    var violationStorage: ViolationStorageProtocol
    var workspaceAnalyzer: WorkspaceAnalyzer?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    var workspaceId: UUID?
    var currentWorkspace: Workspace?
    @ObservationIgnored var isInitialized = false
    @ObservationIgnored var isUpdatingSelection = false
    
    // MARK: - Initialization
    
    init(violationStorage: ViolationStorageProtocol, workspaceAnalyzer: WorkspaceAnalyzer? = nil) {
        self.violationStorage = violationStorage
        self.workspaceAnalyzer = workspaceAnalyzer
        // Mark as initialized after all properties are set
        // This prevents didSet observers from running during initialization
        self.isInitialized = true
    }
    
}
