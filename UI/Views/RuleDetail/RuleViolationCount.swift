//
//  RuleViolationCount.swift
//  SwiftLintRuleStudio
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

/// The rule detail view's "Current Violations" figure: how many unsuppressed violations of one
/// rule the open workspace's stored analysis holds. `RuleDetailView` owns one and loads it from
/// a `.task` keyed on the rule, the workspace and the analyses finished while it is shown.
@MainActor
@Observable
final class RuleViolationCount {
    enum State: Equatable {
        case loading
        case loaded(Int)
        case failed(String)
    }

    private(set) var state: State = .loading

    /// Read the count for `ruleID` from storage.
    ///
    /// With no workspace open nothing is stored, so the count is 0. A reload keeps showing the
    /// last count until the new one arrives, so the section doesn't flash a spinner after every
    /// analysis. A failed read says so rather than showing 0, which would read as a clean rule.
    func load(ruleID: String, workspaceID: UUID?, storage: any ViolationStorageProtocol) async {
        guard let workspaceID else {
            state = .loaded(0)
            return
        }
        let filter = ViolationFilter(ruleIDs: [ruleID], suppression: .unsuppressedOnly)
        do {
            let count = try await storage.getViolationCount(filter: filter, workspaceId: workspaceID)
            // A load superseded by a newer one (another workspace, a finished analysis) leaves
            // the state to the newer load.
            guard !Task.isCancelled else { return }
            state = .loaded(count)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Couldn't load violations: \(error.localizedDescription)")
        }
    }
}
