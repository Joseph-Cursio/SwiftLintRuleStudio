//
//  ConfigComparisonViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for cross-project configuration comparison
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class ConfigComparisonViewModel: ObservableObject {
    @Published var leftWorkspacePath: URL?
    @Published var rightWorkspacePath: URL?
    @Published var comparisonResult: ConfigComparisonResult?
    @Published var isComparing: Bool = false
    @Published var error: Error?

    private let service: ConfigComparisonServiceProtocol

    init(service: ConfigComparisonServiceProtocol, currentWorkspace: Workspace?) {
        self.service = service
        if let workspace = currentWorkspace, let configPath = workspace.configPath {
            self.leftWorkspacePath = configPath
        }
    }

    func selectLeftWorkspace() {
        if let path = selectConfigFile() {
            leftWorkspacePath = path
            comparisonResult = nil
        }
    }

    func selectRightWorkspace() {
        if let path = selectConfigFile() {
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

    private func selectConfigFile() -> URL? {
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
