//
//  RuleListsFixViewModel.swift
//  SwiftLintRuleStudio
//
//  The repair the rule-lists banner offers: preview the rewrite that makes a
//  `.swiftlint.yml` SwiftLint accepts again, then write it.
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

/// Previews and applies `YAMLConfig.normalizedRuleLists()` to one configuration file.
///
/// This is the only path that repairs a file SwiftLint rejects (issue #83). Every other save
/// refuses such a file, so the rewrite — which can turn on rules SwiftLint has been ignoring
/// along with the rest of the file — is always shown before it is written.
@MainActor
@Observable
final class RuleListsFixViewModel {
    /// The rewrite under review: set by `prepareFix()`, cleared by `applyFix()` and `cancel()`.
    var diff: YAMLConfigurationEngine.ConfigDiff?
    /// Why the last prepare or apply failed.
    var errorMessage: String?

    private let configPath: URL
    /// The configuration `diff` previews, written as is by `applyFix()`.
    private var repaired: YAMLConfigurationEngine.YAMLConfig?

    init(configPath: URL) {
        self.configPath = configPath
    }

    /// Reads the file and stages its repair for review. A file that needs none — fixed
    /// since the banner last looked — only announces the change, so the banner refreshes.
    func prepareFix() {
        do {
            let current = try YAMLConfigurationEngine.loadConfig(at: configPath)
            let fixed = current.normalizedRuleLists()
            guard fixed != current else {
                announceChange()
                return
            }
            repaired = fixed
            diff = YAMLConfigurationEngine.diff(from: current, to: fixed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the reviewed repair, backing the file up first, and announces the change.
    func applyFix() {
        guard let repaired else { return }
        do {
            try YAMLConfigurationEngine.save(repaired, to: configPath)
            cancel()
            announceChange()
        } catch {
            // Close the preview first: its presenter shows the alert, which can't appear
            // over the sheet.
            cancel()
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        diff = nil
        repaired = nil
    }

    private func announceChange() {
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleListsRepair": true]
        )
    }
}
