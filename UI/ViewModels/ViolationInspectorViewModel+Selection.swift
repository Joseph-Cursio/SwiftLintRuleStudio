//
//  ViolationInspectorViewModel+Selection.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension ViolationInspectorViewModel {
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
}

extension ViolationInspectorViewModel {
    func syncSelectionFromSet() {
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

    func syncSelectionFromSingle() {
        guard isInitialized, !isUpdatingSelection else { return }
        isUpdatingSelection = true

        if let selectedViolationId {
            selectedViolationIds = [selectedViolationId]
        } else {
            selectedViolationIds.removeAll()
        }

        isUpdatingSelection = false
    }

    func updateSelectionForFilteredViolations(_ filtered: [Violation]) {
        guard isInitialized, !isUpdatingSelection else { return }
        let filteredIds = Set(filtered.map { $0.id })
        let hasInvalidSelection = !selectedViolationIds.isSubset(of: filteredIds)
            || selectedViolationId.map { !filteredIds.contains($0) } ?? false

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

    func setPrimarySelection(_ id: UUID?) {
        guard isInitialized else { return }
        isUpdatingSelection = true
        selectedViolationId = id
        selectedViolationIds = id.map { [$0] } ?? []
        isUpdatingSelection = false
    }
}
