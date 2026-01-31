//
//  WorkspaceAnalyzer+Helpers.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension WorkspaceAnalyzer {
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

    func finalizeAnalysisFailure() {
        isAnalyzing = false
        currentProgress = nil
    }

    func resolveConfigPath(_ configPath: URL?, workspace: Workspace) -> URL? {
        let configPathToUse = configPath ?? workspace.configPath
        if let configPath = configPathToUse,
           FileManager.default.fileExists(atPath: configPath.path) {
            return configPath
        }
        return nil
    }

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

    func makeResult(
        violations: [Violation],
        filesAnalyzed: Int,
        startedAt: Date,
        configHash: String?
    ) -> AnalysisResult {
        let completedAt = Date()
        return AnalysisResult(
            violations: violations,
            filesAnalyzed: filesAnalyzed,
            duration: completedAt.timeIntervalSince(startedAt),
            startedAt: startedAt,
            completedAt: completedAt,
            configHash: configHash
        )
    }

    func resolveFilesToAnalyze(_ filePaths: [URL], onlyChanged: Bool) -> [String] {
        let filePathStrings = filePaths.map { $0.path }
        if onlyChanged {
            return fileTracker.getChangedFiles(from: filePathStrings)
        }
        return filePathStrings
    }

    func analyzeBatches(
        _ filesToAnalyzeURLs: [URL],
        in workspace: Workspace,
        configPath: URL?
    ) async throws -> [Violation] {
        var allViolations: [Violation] = []
        let batchSize = 10

        for batchStart in stride(from: 0, to: filesToAnalyzeURLs.count, by: batchSize) {
            let batch = Array(filesToAnalyzeURLs[batchStart..<min(batchStart + batchSize, filesToAnalyzeURLs.count)])
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
            if path.contains("/.build/") ||
                path.contains("/Pods/") ||
                path.contains("/node_modules/") ||
                path.contains("/.git/") {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.pathExtension.lowercased() == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles
    }

    func parseViolations(from data: Data, workspacePath: URL) throws -> [Violation] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if let string = String(data: data, encoding: .utf8),
               string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            if let string = String(data: data, encoding: .utf8),
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️  Could not parse SwiftLint JSON output")
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
                detectedAt: Date()
            )

            violations.append(violation)
        }

        return violations
    }

    func calculateConfigHash(configPath: URL?) throws -> String? {
        guard let configPath = configPath,
              FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: configPath)
        return data.sha256()
    }
}
