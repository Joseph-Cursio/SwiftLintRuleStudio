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
        if let path = fileSelector() {
            leftWorkspacePath = path
            comparisonResult = nil
        }
    }

    func selectRightWorkspace() {
        if let path = fileSelector() {
            rightWorkspacePath = path
            comparisonResult = nil
        }
    }

    func compare() {
        guard let left = leftWorkspacePath, let right = rightWorkspacePath else { return }

        isComparing = true
        error = nil

        do {
            comparisonResult = try service.compare(
                config1: left,
                label1: left.deletingLastPathComponent().lastPathComponent,
                config2: right,
                label2: right.deletingLastPathComponent().lastPathComponent
            )
        } catch {
            self.error = error
        }
        isComparing = false
    }

    private static func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.yaml]
        panel.title = "Select .swiftlint.yml"
        panel.message = "Choose a SwiftLint configuration file to compare"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
