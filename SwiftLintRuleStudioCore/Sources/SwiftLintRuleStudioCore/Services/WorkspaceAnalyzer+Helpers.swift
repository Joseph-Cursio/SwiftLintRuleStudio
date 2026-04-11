//
//  WorkspaceAnalyzer+Helpers.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

public extension WorkspaceAnalyzer {
    /// Marks the analyzer as actively running and resets progress
    func beginAnalysis() {
        isAnalyzing = true
        currentProgress = AnalysisProgress(
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: nil,
            violationsFound: 0,
            isComplete: false
        )
    }

    /// Records a successful analysis result and marks progress complete
    func finalizeAnalysisSuccess(result: AnalysisResult, violationsCount: Int) {
        lastAnalysisResult = result
        currentProgress = AnalysisProgress(
            currentFile: nil,
            filesProcessed: violationsCount,
            totalFiles: violationsCount,
            violationsFound: violationsCount,
            isComplete: true
        )
        isAnalyzing = false
    }

    /// Clears progress and marks the analyzer as idle after a failure
    func finalizeAnalysisFailure() {
        isAnalyzing = false
        currentProgress = nil
    }

    /// Returns the effective config file path, falling back to the workspace default
    func resolveConfigPath(_ configPath: URL?, workspace: Workspace) -> URL? {
        let configPathToUse = configPath ?? workspace.configPath
        if let configPath = configPathToUse,
           FileManager.default.fileExists(atPath: configPath.path) {
            return configPath
        }
        return nil
    }

    /// Runs SwiftLint and parses the JSON output into violation models
    func runLintAndParse(
        configPath: URL?,
        workspacePath: URL
    ) async throws -> [Violation] {
        let lintData = try await swiftLintCLI.executeLintCommand(
            configPath: configPath,
            workspacePath: workspacePath
        )
        return try parseViolations(from: lintData, workspacePath: workspacePath)
    }

    /// Constructs an `AnalysisResult` from collected violations and timing data
    func makeResult(
        violations: [Violation],
        filesAnalyzed: Int,
        startedAt: Date,
        configHash: String?
    ) -> AnalysisResult {
        let completedAt = Date.now
        return AnalysisResult(
            violations: violations,
            filesAnalyzed: filesAnalyzed,
            duration: completedAt.timeIntervalSince(startedAt),
            startedAt: startedAt,
            completedAt: completedAt,
            configHash: configHash
        )
    }

    /// Filters file paths to only changed files when incremental analysis is requested
    func resolveFilesToAnalyze(_ filePaths: [URL], onlyChanged: Bool) -> [String] {
        let filePathStrings = filePaths.map { $0.path }
        if onlyChanged {
            return fileTracker.getChangedFiles(from: filePathStrings)
        }
        return filePathStrings
    }

    /// Analyzes files in batches, updating progress between each batch
    func analyzeBatches(
        _ filesToAnalyzeURLs: [URL],
        in workspace: Workspace,
        configPath: URL?
    ) async throws -> [Violation] {
        var allViolations: [Violation] = []
        let batchSize = 10

        for batchStart in stride(from: 0, to: filesToAnalyzeURLs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, filesToAnalyzeURLs.count)
            let batch = Array(filesToAnalyzeURLs[batchStart..<batchEnd])
            updateProgress(
                currentFile: batch.first?.lastPathComponent,
                filesProcessed: batchStart,
                totalFiles: filesToAnalyzeURLs.count,
                violationsFound: allViolations.count
            )

            let lintData = try await swiftLintCLI.executeLintCommand(
                configPath: configPath ?? workspace.configPath,
                workspacePath: workspace.path
            )
            let violations = try parseViolations(from: lintData, workspacePath: workspace.path)
            let filteredViolations = filterViolations(
                violations,
                batch: batch,
                workspacePath: workspace.path
            )
            allViolations.append(contentsOf: filteredViolations)
        }

        return allViolations
    }

    /// Updates the current analysis progress snapshot
    func updateProgress(
        currentFile: String?,
        filesProcessed: Int,
        totalFiles: Int,
        violationsFound: Int
    ) {
        currentProgress = AnalysisProgress(
            currentFile: currentFile,
            filesProcessed: filesProcessed,
            totalFiles: totalFiles,
            violationsFound: violationsFound,
            isComplete: false
        )
    }

    /// Filters violations to only those whose file path matches the current batch
    func filterViolations(
        _ violations: [Violation],
        batch: [URL],
        workspacePath: URL
    ) -> [Violation] {
        let batchPaths = Set(batch.map { $0.path })
        return violations.filter { violation in
            let fullPath = workspacePath.appendingPathComponent(violation.filePath).path
            return batchPaths.contains(fullPath)
        }
    }

    /// Recursively finds all `.swift` files in a directory, excluding build artifacts
    func findSwiftFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var swiftFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if DefaultExclusions.pathPatterns.contains(where: { path.contains($0) }) {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.pathExtension.lowercased() == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles
    }

    /// Parses SwiftLint JSON output into an array of `Violation` models
    func parseViolations(from data: Data, workspacePath: URL) throws -> [Violation] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if let string = String(data: data, encoding: .utf8),
               string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            throw WorkspaceAnalyzerError.invalidOutput("Could not parse SwiftLint JSON output")
        }

        var violations: [Violation] = []

        for jsonDict in jsonArray {
            guard let filePath = jsonDict["file"] as? String,
                  let line = jsonDict["line"] as? Int,
                  let ruleID = jsonDict["rule_id"] as? String ?? jsonDict["type"] as? String,
                  let severityString = jsonDict["severity"] as? String,
                  let message = jsonDict["reason"] as? String ?? jsonDict["message"] as? String else {
                continue
            }

            let severity = Severity(rawValue: severityString.lowercased()) ?? .warning
            let column = jsonDict["character"] as? Int

            let fullPath = URL(fileURLWithPath: filePath)
            let relativePath: String
            if fullPath.path.hasPrefix(workspacePath.path) {
                let relative = fullPath.path.dropFirst(workspacePath.path.count)
                relativePath = relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
            } else {
                relativePath = filePath
            }

            let violation = Violation(
                ruleID: ruleID,
                filePath: relativePath,
                line: line,
                column: column,
                severity: severity,
                message: message,
                detectedAt: Date.now
            )

            violations.append(violation)
        }

        return violations
    }

    /// Computes a SHA-256 hash of the config file for change detection
    func calculateConfigHash(configPath: URL?) throws -> String? {
        guard let configPath = configPath,
              FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: configPath)
        return data.sha256()
    }
}
