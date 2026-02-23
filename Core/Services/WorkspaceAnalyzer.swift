//
//  WorkspaceAnalyzer.swift
//  SwiftLintRuleStudio
//
//  Background analysis engine that runs SwiftLint and tracks violations
//

import Foundation
import Combine

/// Service for analyzing workspaces with SwiftLint
@MainActor
class WorkspaceAnalyzer: ObservableObject {
    
    // MARK: - Properties
    
    @Published var isAnalyzing: Bool = false
    @Published var currentProgress: AnalysisProgress?
    @Published var lastAnalysisResult: AnalysisResult?
    
    let swiftLintCLI: SwiftLintCLIProtocol
    let violationStorage: ViolationStorageProtocol
    let fileTracker: FileTracker
    var currentAnalysisTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(
        swiftLintCLI: SwiftLintCLIProtocol,
        violationStorage: ViolationStorageProtocol,
        fileTracker: FileTracker? = nil
    ) {
        self.swiftLintCLI = swiftLintCLI
        self.violationStorage = violationStorage
        
        // Create file tracker with cache in app support directory
        if let providedTracker = fileTracker {
            self.fileTracker = providedTracker
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let cacheDir = appSupport.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let cacheURL = cacheDir.appendingPathComponent("file_tracker_cache.json")
            self.fileTracker = FileTracker(cacheURL: cacheURL)
        }
    }

    /// Analyze a workspace for violations
    /// - Parameters:
    ///   - workspace: The workspace to analyze
    ///   - configPath: Optional path to SwiftLint configuration file
    /// - Returns: Analysis result with violations
    func analyze(
        workspace: Workspace,
        configPath: URL? = nil
    ) async throws -> AnalysisResult {
        cancelAnalysis()
        let startedAt = Date()
        beginAnalysis()

        do {
            let actualConfigPath = resolveConfigPath(configPath, workspace: workspace)
            let violations = try await runLintAndParse(
                configPath: actualConfigPath,
                workspacePath: workspace.path
            )
            let configHash = try calculateConfigHash(configPath: configPath ?? workspace.configPath)
            try await violationStorage.storeViolations(violations, for: workspace.id)

            let result = makeResult(
                violations: violations,
                filesAnalyzed: Set(violations.map { $0.filePath }).count,
                startedAt: startedAt,
                configHash: configHash
            )
            finalizeAnalysisSuccess(result: result, violationsCount: violations.count)
            return result
        } catch {
            finalizeAnalysisFailure()
            throw WorkspaceAnalyzerError.analysisFailed(error.localizedDescription)
        }
    }

    /// Analyze specific files incrementally
    /// Only analyzes files that have changed since last analysis
    func analyzeFiles(
        _ filePaths: [URL],
        in workspace: Workspace,
        configPath: URL? = nil,
        onlyChanged: Bool = true
    ) async throws -> AnalysisResult {
        let startedAt = Date()
        isAnalyzing = true

        let filesToAnalyze = resolveFilesToAnalyze(filePaths, onlyChanged: onlyChanged)
        guard !filesToAnalyze.isEmpty else {
            let result = makeResult(
                violations: [],
                filesAnalyzed: 0,
                startedAt: startedAt,
                configHash: nil
            )
            isAnalyzing = false
            return result
        }

        let filesToAnalyzeURLs = filesToAnalyze.map { URL(fileURLWithPath: $0) }
        let allViolations = try await analyzeBatches(
            filesToAnalyzeURLs,
            in: workspace,
            configPath: configPath
        )

        try fileTracker.updateTracking(for: filesToAnalyze)
        try await violationStorage.storeViolations(allViolations, for: workspace.id)

        let result = makeResult(
            violations: allViolations,
            filesAnalyzed: filesToAnalyze.count,
            startedAt: startedAt,
            configHash: nil
        )

        lastAnalysisResult = result
        isAnalyzing = false
        return result
    }

    /// Analyze only changed files in workspace
    func analyzeChangedFiles(
        in workspace: Workspace,
        configPath: URL? = nil
    ) async throws -> AnalysisResult {
        let swiftFiles = try findSwiftFiles(in: workspace.path)
        return try await analyzeFiles(
            swiftFiles,
            in: workspace,
            configPath: configPath,
            onlyChanged: true
        )
    }

    /// Cancel current analysis
    func cancelAnalysis() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isAnalyzing = false
        currentProgress = nil
    }
}
