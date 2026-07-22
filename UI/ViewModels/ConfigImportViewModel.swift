//
//  ConfigImportViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for importing configs from URLs
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

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

    /// The in-flight preview fetch, if any. Cancelled and replaced on
    /// re-invocation so a superseded fetch cannot overwrite the newer one's result.
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?

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

        fetchTask?.cancel()
        isFetching = true
        error = nil
        preview = nil
        importComplete = false

        fetchTask = Task {
            do {
                let fetched = try await importService.fetchAndPreview(from: url, currentConfigPath: configPath)
                // Superseded by a newer fetch — leave the newer run's state alone.
                guard !Task.isCancelled else { return }
                preview = fetched
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
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
