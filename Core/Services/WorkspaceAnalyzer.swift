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
    private var currentAnalysisTask: Task<Void, Never>?
    // Stores a cancel action for the in-flight analyze() call so that
    // cancelAnalysis() can reach it even though analyze() returns a value.
    private var pendingAnalysisCancellation: (@Sendable () -> Void)?

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
        let startedAt = Date.now
        beginAnalysis()

        // Wrap the body in a Task so cancelAnalysis() can reach it externally.
        // The Task inherits @MainActor from this method's context.
        let task = Task<AnalysisResult, Error> {
            do {
                let actualConfigPath = self.resolveConfigPath(configPath, workspace: workspace)
                let violations = try await self.runLintAndParse(
                    configPath: actualConfigPath,
                    workspacePath: workspace.path
                )
                let configHash = try self.calculateConfigHash(configPath: configPath ?? workspace.configPath)
                try await self.violationStorage.storeViolations(violations, for: workspace.id)

                let result = self.makeResult(
                    violations: violations,
                    filesAnalyzed: Set(violations.map { $0.filePath }).count,
                    startedAt: startedAt,
                    configHash: configHash
                )
                self.finalizeAnalysisSuccess(result: result, violationsCount: violations.count)
                return result
            } catch {
                self.finalizeAnalysisFailure()
                throw WorkspaceAnalyzerError.analysisFailed(error.localizedDescription)
            }
        }

        // Store a cancel hook so cancelAnalysis() can cancel this task directly.
        pendingAnalysisCancellation = { task.cancel() }
        defer { pendingAnalysisCancellation = nil }

        // Also propagate cancellation if the *caller's* task is cancelled.
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
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
        let startedAt = Date.now
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
        pendingAnalysisCancellation?()
        pendingAnalysisCancellation = nil
        isAnalyzing = false
        currentProgress = nil
    }
}
