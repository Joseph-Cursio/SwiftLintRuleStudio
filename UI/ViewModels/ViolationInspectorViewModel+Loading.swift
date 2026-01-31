//
//  ViolationInspectorViewModel+Loading.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Combine

extension ViolationInspectorViewModel {
    func loadViolations(for workspaceId: UUID, workspace: Workspace? = nil) async throws {
        self.workspaceId = workspaceId
        if let workspace = workspace {
            self.currentWorkspace = workspace
        }

        if let workspace = workspace ?? currentWorkspace,
           let analyzer = workspaceAnalyzer {
            subscribeToAnalyzer(analyzer)
            do {
                _ = try await analyzer.analyze(workspace: workspace, configPath: workspace.configPath)
            } catch {
                print("❌ Error analyzing workspace: \(error.localizedDescription)")
            }
        }

        let fetched = try await violationStorage.fetchViolations(
            filter: ViolationFilter(),
            workspaceId: workspaceId
        )
        violations = fetched
        updateFilteredViolations()
    }

    func refreshViolations() async throws {
        guard let workspaceId = workspaceId,
              let workspace = currentWorkspace,
              let analyzer = workspaceAnalyzer else {
            try await reloadViolationsFromStorage()
            return
        }

        do {
            _ = try await analyzer.analyze(workspace: workspace, configPath: workspace.configPath)
        } catch {
            print("Error analyzing workspace: \(error)")
            throw error
        }

        try await loadViolations(for: workspaceId, workspace: workspace)
    }

    func clearViolations() {
        violations = []
        filteredViolations = []
        workspaceId = nil
        selectedViolationId = nil
        selectedViolationIds.removeAll()
    }
}

private extension ViolationInspectorViewModel {
    func subscribeToAnalyzer(_ analyzer: WorkspaceAnalyzer) {
        analyzer.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analyzing in
                self?.isAnalyzing = analyzing
            }
            .store(in: &cancellables)
    }

    func reloadViolationsFromStorage() async throws {
        guard let workspaceId = workspaceId else { return }
        let fetched = try await violationStorage.fetchViolations(
            filter: ViolationFilter(),
            workspaceId: workspaceId
        )
        violations = fetched
        updateFilteredViolations()
    }
}
