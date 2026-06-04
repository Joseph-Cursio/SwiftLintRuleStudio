//
//  ConfigMapViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for the Config Map: discovers the workspace's nested .swiftlint.yml
//  tree and resolves the effective config for a selected folder. The heavy
//  lifting lives in Core (ConfigTreeDiscovery / ResolvedConfigurationEngine /
//  ConfigMapPresenter); this is a thin orchestration layer.
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

@MainActor
@Observable
class ConfigMapViewModel {
    /// Sparse config-tree rows for the sidebar list.
    var treeRows: [ConfigTreeRow] = []
    /// The selected config row (drives the inspector).
    var selectedRowID: UUID?
    /// The resolved-config inspector content for the selected folder.
    var resolvedDisplay: ResolvedConfigDisplay?
    /// Advisories for the selected config (e.g. a custom rule shadowing a built-in).
    var conflicts: [CustomRuleConflict] = []
    var isLoading: Bool = false

    /// Whether a workspace is open to map.
    var hasWorkspace: Bool { workspacePath != nil }

    private let workspacePath: URL?
    private let builtInRuleIdentifiers: Set<String>
    private let discovery = ConfigTreeDiscovery()
    private let engine = ResolvedConfigurationEngine()
    private let presenter = ConfigMapPresenter()
    private let conflictDetector = CustomRuleConflictDetector()
    private var tree: ConfigTree?

    init(workspacePath: URL?, builtInRuleIdentifiers: Set<String> = []) {
        self.workspacePath = workspacePath
        self.builtInRuleIdentifiers = builtInRuleIdentifiers
    }

    /// Discovers the config tree and selects the root config (if any).
    func load() {
        guard let workspacePath = workspacePath else {
            tree = nil
            treeRows = []
            resolvedDisplay = nil
            conflicts = []
            selectedRowID = nil
            return
        }
        isLoading = true
        let discovered = discovery.discover(in: workspacePath)
        tree = discovered
        treeRows = presenter.treeRows(for: discovered)
        isLoading = false

        if let initialRow = treeRows.first(where: \.isRoot) ?? treeRows.first {
            select(rowID: initialRow.id)
        } else {
            selectedRowID = nil
            resolvedDisplay = nil
        }
    }

    /// Resolves and presents the effective config for the selected config's folder,
    /// and computes any advisories for that config.
    func select(rowID: UUID) {
        selectedRowID = rowID
        guard let tree = tree,
              let config = tree.configs.first(where: { $0.id == rowID }) else {
            resolvedDisplay = nil
            conflicts = []
            return
        }
        let resolved = engine.resolve(at: config.directoryPath, in: tree)
        resolvedDisplay = presenter.display(for: resolved, in: tree)

        if let parsed = config.config {
            conflicts = conflictDetector.conflicts(
                in: parsed,
                builtInRuleIdentifiers: builtInRuleIdentifiers
            )
        } else {
            conflicts = []
        }
    }
}
