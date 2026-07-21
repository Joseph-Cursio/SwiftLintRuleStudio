//
//  ViolationInspectorViewModel+Loading.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Combine
import Foundation
#if os(macOS)
import AppKit
import SwiftLintRuleStudioCore
import UserNotifications
#endif

extension ViolationInspectorViewModel {
    func loadViolations(for workspaceId: UUID, workspace: Workspace? = nil) async throws {
        self.workspaceId = workspaceId
        if let workspace = workspace {
            self.currentWorkspace = workspace
        }

        if let workspace = workspace ?? currentWorkspace,
           let analyzer = workspaceAnalyzer {
            subscribeToAnalyzer(analyzer)
            _ = try? await analyzer.analyze(workspace: workspace, configPath: workspace.configPath)
        }

        let fetched = try await violationStorage.fetchViolations(
            filter: ViolationFilter(),
            workspaceId: workspaceId
        )
        // A newer load may have switched the active workspace while we awaited
        // analysis and the fetch; don't clobber its results with this stale load.
        guard self.workspaceId == workspaceId else { return }
        violations = fetched
        updateFilteredViolations()
#if os(macOS)
        NSApp.dockTile.badgeLabel = fetched.isEmpty ? nil : "\(fetched.count)"
        await postAnalysisCompleteNotification(count: fetched.count)
#endif
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
#if os(macOS)
        NSApp.dockTile.badgeLabel = nil
#endif
    }

    /// Repaint the violation list from storage without re-running analysis. Used
    /// after suppress/resolve — those are pure DB mutations, so re-linting the whole
    /// workspace just to reflect them would be wasteful (and, before the storage
    /// upsert, actively discarded the change).
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

private extension ViolationInspectorViewModel {
    func subscribeToAnalyzer(_ analyzer: any WorkspaceAnalyzerProtocol) {
        analyzer.isAnalyzingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] analyzing in
                self?.isAnalyzing = analyzing
            }
            .store(in: &cancellables)
    }

#if os(macOS)
    func postAnalysisCompleteNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Analysis Complete"
        content.body = count == 0
            ? "No violations found"
            : "\(count) violation\(count == 1 ? "" : "s") found"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
#endif
}
