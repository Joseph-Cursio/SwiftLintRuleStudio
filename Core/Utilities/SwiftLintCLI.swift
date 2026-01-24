//
//  SwiftLintCLI.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

typealias SwiftLintCommandRunner = @Sendable (String, [String]) async throws -> (Data, Data)
typealias SwiftLintFileExists = @Sendable (String) async -> Bool
typealias SwiftLintProcessRunner = @Sendable (URL, [String], [String: String]) async throws -> (Data, Data)
typealias SwiftLintShellRunner = @Sendable (String, [String], [String: String]) async throws -> (Data, Data)

/// Protocol for SwiftLint CLI operations
protocol SwiftLintCLIProtocol {
    func detectSwiftLintPath() async throws -> URL
    func executeRulesCommand() async throws -> Data
    func executeRuleDetailCommand(ruleId: String) async throws -> Data
    func generateDocsForRule(ruleId: String) async throws -> String
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data
    func getVersion() async throws -> String
}

/// Service for executing SwiftLint CLI commands
actor SwiftLintCLI: SwiftLintCLIProtocol {
    private var cachedSwiftLintPath: URL?
    let cacheManager: CacheManager
    let commandRunner: SwiftLintCommandRunner?
    let fileExists: SwiftLintFileExists
    let processRunner: SwiftLintProcessRunner?
    let shellRunner: SwiftLintShellRunner?
    
    init(
        cacheManager: CacheManagerProtocol? = nil,
        commandRunner: SwiftLintCommandRunner? = nil,
        fileExists: SwiftLintFileExists? = nil,
        processRunner: SwiftLintProcessRunner? = nil,
        shellRunner: SwiftLintShellRunner? = nil
    ) {
        // Use provided cache manager or create a default one
        // Store as concrete CacheManager type to avoid protocol existential isolation issues
        // CacheManager is a struct (value type) and Sendable, so it can cross actor boundaries
        if let provided = cacheManager as? CacheManager {
            self.cacheManager = provided
        } else {
            self.cacheManager = CacheManager()
        }
        self.commandRunner = commandRunner
        self.fileExists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        self.processRunner = processRunner
        self.shellRunner = shellRunner
    }
    
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func detectSwiftLintPath() async throws -> URL {
        // Check cache first (fast path) - synchronous check is fine for cached paths
        if let cached = cachedSwiftLintPath, await fileExists(cached.path) {
            return cached
        } else if cachedSwiftLintPath != nil {
            cachedSwiftLintPath = nil
        }
        
        // Try common locations - synchronous checks should be instant for local paths
        // These are standard system paths, not network mounts, so they should be fast
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",  // Apple Silicon Homebrew (most common)
            "/usr/local/bin/swiftlint",     // Intel Homebrew
            "/usr/bin/swiftlint"            // System installation
        ]
        
        // Check paths synchronously - these are local paths and should be instant
        for pathString in possiblePaths where await fileExists(pathString) {
            let url = URL(fileURLWithPath: pathString)
            cachedSwiftLintPath = url
            return url
        }
        
        // If we get here, SwiftLint wasn't found in common locations
        throw SwiftLintError.notFound
    }
    
    func executeRulesCommand() async throws -> Data {
        // Use "swiftlint" command directly - let shell PATH resolve it
        // This works better with sandboxed apps
        return try await executeCommandViaShell(command: "swiftlint", arguments: ["rules"])
    }
    
    func executeRuleDetailCommand(ruleId: String) async throws -> Data {
        return try await executeCommandViaShell(command: "swiftlint", arguments: ["rules", ruleId])
    }
    
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        let arguments = await Self.buildLintArguments(
            configPath: configPath,
            workspacePath: workspacePath,
            fileExists: fileExists
        )
        return try await executeCommandViaShell(command: "swiftlint", arguments: arguments)
    }
    
    func getVersion() async throws -> String {
        let data = try await executeCommandViaShell(command: "swiftlint", arguments: ["version"])
        guard let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SwiftLintError.invalidVersion
        }
        return version
    }
    
}

enum SwiftLintError: LocalizedError {
    case notFound
    case invalidVersion
    case executionFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return """
            SwiftLint not found. Please install SwiftLint using one of these methods:
            
            • Homebrew: brew install swiftlint
            • Mint: mint install realm/SwiftLint
            • CocoaPods: Add to your Podfile
            • Direct download: https://github.com/realm/SwiftLint/releases
            
            After installing, restart SwiftLint Rule Studio.
            """
        case .invalidVersion:
            return "Could not determine SwiftLint version."
        case .executionFailed(let message):
            return "SwiftLint execution failed: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            return "Install SwiftLint using Homebrew: brew install swiftlint"
        default:
            return nil
        }
    }
}
