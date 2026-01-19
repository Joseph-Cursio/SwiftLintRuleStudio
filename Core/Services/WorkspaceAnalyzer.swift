//
//  WorkspaceAnalyzer.swift
//  SwiftLintRuleStudio
//
//  Background analysis engine that runs SwiftLint and tracks violations
//

import Foundation
import Combine

/// Result of a workspace analysis
struct AnalysisResult {
    let violations: [Violation]
    let filesAnalyzed: Int
    let duration: TimeInterval
    let startedAt: Date
    let completedAt: Date
    let configHash: String?
    
    init(
        violations: [Violation],
        filesAnalyzed: Int,
        duration: TimeInterval,
        startedAt: Date,
        completedAt: Date,
        configHash: String? = nil
    ) {
        self.violations = violations
        self.filesAnalyzed = filesAnalyzed
        self.duration = duration
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.configHash = configHash
    }
}

/// Analysis progress information
struct AnalysisProgress {
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int?
    let violationsFound: Int
    let isComplete: Bool
    
    var progress: Double {
        guard let total = totalFiles, total > 0 else { return 0.0 }
        return Double(filesProcessed) / Double(total)
    }
}

/// Service for analyzing workspaces with SwiftLint
@MainActor
class WorkspaceAnalyzer: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var currentProgress: AnalysisProgress?
    @Published private(set) var lastAnalysisResult: AnalysisResult?
    
    private let swiftLintCLI: SwiftLintCLIProtocol
    private let violationStorage: ViolationStorageProtocol
    private let fileTracker: FileTracker
    private var currentAnalysisTask: Task<Void, Never>?
    
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
    
    // MARK: - Analysis
    
    /// Analyze a workspace for violations
    /// - Parameters:
    ///   - workspace: The workspace to analyze
    ///   - configPath: Optional path to SwiftLint configuration file
    ///   - scope: Analysis scope (nil = entire workspace)
    /// - Returns: Analysis result with violations
    func analyze(
        workspace: Workspace,
        configPath: URL? = nil,
        scope: AnalysisScope? = nil
    ) async throws -> AnalysisResult {
        // Cancel any existing analysis
        cancelAnalysis()
        
        let startedAt = Date()
        isAnalyzing = true
        
        // Update progress
        currentProgress = AnalysisProgress(
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: nil,
            violationsFound: 0,
            isComplete: false
        )
        
        do {
            // Execute SwiftLint
            let configPathToUse = configPath ?? workspace.configPath
            // Verify config file exists before using it
            let actualConfigPath: URL?
            if let configPath = configPathToUse,
               FileManager.default.fileExists(atPath: configPath.path) {
                actualConfigPath = configPath
            } else {
                actualConfigPath = nil
            }
            
            let lintData = try await swiftLintCLI.executeLintCommand(
                configPath: actualConfigPath,
                workspacePath: workspace.path
            )
            
            // Parse violations from JSON output
            let violations = try parseViolations(from: lintData, workspacePath: workspace.path)
            
            // Calculate config hash if config exists
            let configHash = try calculateConfigHash(configPath: configPath ?? workspace.configPath)
            
            // Store violations in database
            try await violationStorage.storeViolations(violations, for: workspace.id)
            
            // Create analysis result
            let completedAt = Date()
            let duration = completedAt.timeIntervalSince(startedAt)
            
            let result = AnalysisResult(
                violations: violations,
                filesAnalyzed: Set(violations.map { $0.filePath }).count,
                duration: duration,
                startedAt: startedAt,
                completedAt: completedAt,
                configHash: configHash
            )
            
            // Update state
            lastAnalysisResult = result
            currentProgress = AnalysisProgress(
                currentFile: nil,
                filesProcessed: violations.count,
                totalFiles: violations.count,
                violationsFound: violations.count,
                isComplete: true
            )
            
            isAnalyzing = false
            return result
            
        } catch {
            isAnalyzing = false
            currentProgress = nil
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
        
        // Convert URLs to file paths
        let filePathStrings = filePaths.map { $0.path }
        
        // Filter to only changed files if requested
        let filesToAnalyze: [String]
        if onlyChanged {
            filesToAnalyze = fileTracker.getChangedFiles(from: filePathStrings)
        } else {
            filesToAnalyze = filePathStrings
        }
        
        // If no files changed, return empty result
        guard !filesToAnalyze.isEmpty else {
            let completedAt = Date()
            let result = AnalysisResult(
                violations: [],
                filesAnalyzed: 0,
                duration: completedAt.timeIntervalSince(startedAt),
                startedAt: startedAt,
                completedAt: completedAt
            )
            isAnalyzing = false
            return result
        }
        
        // Convert back to URLs for SwiftLint
        let filesToAnalyzeURLs = filesToAnalyze.compactMap { URL(fileURLWithPath: $0) }
        
        var allViolations: [Violation] = []
        
        // Analyze files in batches for performance
        let batchSize = 10
        for batchStart in stride(from: 0, to: filesToAnalyzeURLs.count, by: batchSize) {
            let batch = Array(filesToAnalyzeURLs[batchStart..<min(batchStart + batchSize, filesToAnalyzeURLs.count)])
            
            // Update progress
            currentProgress = AnalysisProgress(
                currentFile: batch.first?.lastPathComponent,
                filesProcessed: batchStart,
                totalFiles: filesToAnalyzeURLs.count,
                violationsFound: allViolations.count,
                isComplete: false
            )
            
            // Run SwiftLint on batch of files
            // Note: SwiftLint doesn't support analyzing specific files directly,
            // so we'll need to use the workspace path and filter results
            let lintData = try await swiftLintCLI.executeLintCommand(
                configPath: configPath ?? workspace.configPath,
                workspacePath: workspace.path
            )
            
            let violations = try parseViolations(from: lintData, workspacePath: workspace.path)
            
            // Filter violations to only include files we're analyzing
            let batchPaths = Set(batch.map { $0.path })
            let filteredViolations = violations.filter { violation in
                let fullPath = workspace.path.appendingPathComponent(violation.filePath).path
                return batchPaths.contains(fullPath)
            }
            
            allViolations.append(contentsOf: filteredViolations)
        }
        
        // Update file tracking for analyzed files
        try fileTracker.updateTracking(for: filesToAnalyze)
        
        // Store violations
        try await violationStorage.storeViolations(allViolations, for: workspace.id)
        
        let completedAt = Date()
        let result = AnalysisResult(
            violations: allViolations,
            filesAnalyzed: filesToAnalyze.count,
            duration: completedAt.timeIntervalSince(startedAt),
            startedAt: startedAt,
            completedAt: completedAt
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
        // Find all Swift files in workspace
        let swiftFiles = try findSwiftFiles(in: workspace.path)
        
        // Analyze only changed files
        return try await analyzeFiles(
            swiftFiles,
            in: workspace,
            configPath: configPath,
            onlyChanged: true
        )
    }
    
    /// Find all Swift files in a directory
    private func findSwiftFiles(in directory: URL) throws -> [URL] {
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
            // Skip common build and dependency directories
            let path = fileURL.path
            if path.contains("/.build/") || 
               path.contains("/Pods/") || 
               path.contains("/node_modules/") ||
               path.contains("/.git/") {
                enumerator.skipDescendants()
                continue
            }
            
            // Check if it's a Swift file
            if fileURL.pathExtension.lowercased() == "swift" {
                swiftFiles.append(fileURL)
            }
        }
        
        return swiftFiles
    }
    
    /// Cancel current analysis
    func cancelAnalysis() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isAnalyzing = false
        currentProgress = nil
    }
    
    // MARK: - Private Methods
    
    private func parseViolations(from data: Data, workspacePath: URL) throws -> [Violation] {
        // SwiftLint JSON output format:
        // [{"file":"path","line":1,"character":1,"severity":"error","type":"rule_id","rule_id":"rule_id","reason":"message"}]
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // If not JSON array, might be empty or error - return empty array
            if let string = String(data: data, encoding: .utf8),
               string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            // Log error only if it's not empty
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
            
            // Convert file path to relative path from workspace
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
    
    private func calculateConfigHash(configPath: URL?) throws -> String? {
        guard let configPath = configPath,
              FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: configPath)
        return data.sha256()
    }
}

// MARK: - Analysis Scope

enum AnalysisScope {
    case workspace
    case files([URL])
    case directory(URL)
}

// MARK: - Errors

enum WorkspaceAnalyzerError: LocalizedError {
    case analysisFailed(String)
    case invalidOutput(String)
    case workspaceNotFound
    case swiftLintNotFound
    
    var errorDescription: String? {
        switch self {
        case .analysisFailed(let message):
            return "Analysis failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid SwiftLint output: \(message)"
        case .workspaceNotFound:
            return "Workspace not found"
        case .swiftLintNotFound:
            return "SwiftLint binary not found"
        }
    }
}

// MARK: - Data Extension

import CryptoKit

extension Data {
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

