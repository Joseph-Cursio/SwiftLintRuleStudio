//
//  ConfigImportViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for importing configs from URLs
//

import Foundation
import Observation

@MainActor
@Observable
class ConfigImportViewModel {
    var urlString: String = ""
    var preview: ConfigImportPreview?
    var importMode: ImportMode = .merge
    var isFetching: Bool = false
    var isImporting: Bool = false
    var error: Error?
    var importComplete: Bool = false

    private let importService: ConfigImportServiceProtocol
    private let configPath: URL?

    init(importService: ConfigImportServiceProtocol, configPath: URL?) {
        self.importService = importService
        self.configPath = configPath
    }

    func fetchPreview() {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            error = URLConfigFetcherError.invalidURL
            return
        }

        isFetching = true
        error = nil
        preview = nil
        importComplete = false

        Task {
            do {
                preview = try await importService.fetchAndPreview(from: url, currentConfigPath: configPath)
            } catch {
                self.error = error
            }
            isFetching = false
        }
    }

    func applyImport() {
        guard let preview = preview, let configPath = configPath else { return }

        isImporting = true
        error = nil

        do {
            try importService.applyImport(preview: preview, mode: importMode, to: configPath)
            importComplete = true
        } catch {
            self.error = error
        }
        isImporting = false
    }
}
