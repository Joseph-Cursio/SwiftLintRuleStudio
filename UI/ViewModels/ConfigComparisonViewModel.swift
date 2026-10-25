//
//  ConfigComparisonViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for cross-project configuration comparison
//

import AppKit
import Foundation
import Observation
import SwiftLintRuleStudioCore
import UniformTypeIdentifiers

/// A folder picked for comparison that has no SwiftLint configuration.
enum ConfigSelectionError: LocalizedError {
    case noConfig(folder: URL)

    var errorDescription: String? {
        switch self {
        case .noConfig(let folder):
            "\(folder.lastPathComponent) has no .swiftlint.yml. "
                + "Choose a project folder that has one, or the file itself."
        }
    }
}

@MainActor
@Observable
class ConfigComparisonViewModel {
    var leftWorkspacePath: URL?
    var rightWorkspacePath: URL?
    var comparisonResult: ConfigComparisonResult?
    var isComparing: Bool = false
    var error: Error?

    private let service: ConfigComparisonServiceProtocol
    private let fileSelector: @MainActor () -> URL?

    init(
        service: ConfigComparisonServiceProtocol,
        currentWorkspace: Workspace?,
        fileSelector: (@MainActor () -> URL?)? = nil
    ) {
        self.service = service
        self.fileSelector = fileSelector ?? Self.presentOpenPanel
        if let workspace = currentWorkspace, let configPath = workspace.configPath {
            self.leftWorkspacePath = configPath
        }
    }

    func selectLeftWorkspace() {
        if let path = chooseConfig() {
            leftWorkspacePath = path
            comparisonResult = nil
        }
    }

    func selectRightWorkspace() {
        if let path = chooseConfig() {
            rightWorkspacePath = path
            comparisonResult = nil
        }
    }

    /// What each side is called in the comparison: the name of the folder its file is in. Two
    /// clones of one repo, or two files in one folder, would get the same name, so then the
    /// files are told apart by file name, or else by the folders above; the same file twice is
    /// Left and Right.
    static func labels(for left: URL, _ right: URL) -> (left: String, right: String) {
        let leftFolder = left.deletingLastPathComponent()
        let rightFolder = right.deletingLastPathComponent()
        if leftFolder.lastPathComponent != rightFolder.lastPathComponent {
            return (leftFolder.lastPathComponent, rightFolder.lastPathComponent)
        }
        if left.lastPathComponent != right.lastPathComponent {
            return (left.lastPathComponent, right.lastPathComponent)
        }
        let leftParts = Array(leftFolder.pathComponents.filter { $0 != "/" }.reversed())
        let rightParts = Array(rightFolder.pathComponents.filter { $0 != "/" }.reversed())
        for depth in 2...max(leftParts.count, rightParts.count, 2) {
            let leftLabel = leftParts.prefix(depth).reversed().joined(separator: "/")
            let rightLabel = rightParts.prefix(depth).reversed().joined(separator: "/")
            if leftLabel != rightLabel {
                return (leftLabel, rightLabel)
            }
        }
        return ("Left", "Right")
    }

    /// `knownRules` is the rule catalog, which says for certain which rules are opt-in.
    func compare(knownRules: [Rule] = []) {
        guard let left = leftWorkspacePath, let right = rightWorkspacePath else { return }

        isComparing = true
        error = nil

        let labels = Self.labels(for: left, right)
        do {
            comparisonResult = try service.compare(
                config1: left,
                label1: labels.left,
                config2: right,
                label2: labels.right,
                knownRules: knownRules
            )
        } catch {
            self.error = error
        }
        isComparing = false
    }

    /// The config the user picked: the file itself, or a project folder's `.swiftlint.yml`.
    private func chooseConfig() -> URL? {
        guard let picked = fileSelector() else { return nil }
        do {
            return try Self.configFile(for: picked)
        } catch {
            self.error = error
            return nil
        }
    }

    static func configFile(for picked: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return picked }
        let config = picked.appendingPathComponent(".swiftlint.yml")
        guard FileManager.default.fileExists(atPath: config.path) else {
            throw ConfigSelectionError.noConfig(folder: picked)
        }
        return config
    }

    /// Accepts a project folder as well as a YAML file, and shows hidden files: the file
    /// everyone wants is `.swiftlint.yml`, which macOS hides because of its leading dot.
    private static func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.yaml, .folder]
        panel.title = "Choose a SwiftLint Configuration"
        panel.message = "Choose a project folder, or its .swiftlint.yml file"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
